#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

#define MAX_ROUTES  22
#define MAX_COST    17
#define DV_TTL       4


module RoutingTableP {
    provides interface RoutingTable;
    
    uses interface SimpleSend as Sender;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface Timer<TMilli> as DVRTimer;
    uses interface Random as Random;
    uses interface Transport;
}

implementation {

    typedef struct {
        uint8_t dest;
        uint8_t nextHop;
        uint8_t cost;
        uint8_t ttl;
    } Route;
    
    uint16_t numRoutes = 0;
    Route routingTable[MAX_ROUTES];
    pack routePack;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, void *payload, uint8_t length);
    void initilizeRoutingTable();
    uint8_t findNextHop(uint8_t dest);
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost, uint8_t ttl);
    void removeRoute(uint8_t idx);
    void decrementTTLs();
    bool inputNeighbors();
    void triggerUpdate();
    
    command error_t RoutingTable.start() {
        initilizeRoutingTable();
        call DVRTimer.startOneShot(40000);
        dbg(ROUTING_CHANNEL, "Distance Vector Routing Started on node %u!\n", TOS_NODE_ID);
        return SUCCESS;
    }

    event void DVRTimer.fired() {
        if(call DVRTimer.isOneShot()) {
            call DVRTimer.startPeriodic(30000 + (uint16_t) (call Random.rand16()%5000));
        } else {
            // Decrement TTLs
            decrementTTLs();
            // Input neighbors into the routing table, if not there
            if(!inputNeighbors())
                // Send out routing table
                triggerUpdate();
        }
    }

    command void RoutingTable.ping(uint16_t destination, uint8_t *payload) {
        makePack(&routePack, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
        logPack(&routePack);
        call RoutingTable.routePacket(&routePack);
    }

    command void RoutingTable.routePacket(pack* myMsg) {
        uint8_t nextHop;
        if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "PING Packet has reached destination %d!!!\n", TOS_NODE_ID);
            makePack(&routePack, myMsg->dest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call RoutingTable.routePacket(&routePack);
            return;
        } else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(ROUTING_CHANNEL, "PING_REPLY Packet has reached destination %d!!!\n", TOS_NODE_ID);
            return;
        } else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_TCP) {
            dbg(ROUTING_CHANNEL, "TCP Packet has reached destination %d!!!\n", TOS_NODE_ID);
            call Transport.receive(myMsg);
            return;
        }
        if((nextHop = findNextHop(myMsg->dest))) {
            dbg(ROUTING_CHANNEL, "Node %d routing packet through %d\n", TOS_NODE_ID, nextHop);
            //logPack(myMsg);
            call Sender.send(*myMsg, nextHop);
        } else {
            dbg(ROUTING_CHANNEL, "No route to destination. Dropping packet...\n");
            //logPack(myMsg);
        }
    }

    // Update the routing table if needed
    command void RoutingTable.handleDV(pack* myMsg) {
        uint16_t i, j;
        bool routePresent = FALSE, routesAdded = FALSE;
        Route* receivedRoutes = (Route*) myMsg->payload;
        // For each of up to 5 routes -> process the routes
        for(i = 0; i < 5; i++) {
            // Reached the last route -> stop
            if(receivedRoutes[i].dest == 0) { break; }
            // Process the route
            for(j = 0; j < numRoutes; j++) {
                if(receivedRoutes[i].dest == routingTable[j].dest) {
                    // If Split Horizon packet -> do nothing
                    // If sender is the source of table entry -> update
                    // If more optimal route found -> update
                    if(receivedRoutes[i].nextHop != 0) {
                        if(routingTable[j].nextHop == myMsg->src) {
                            routingTable[j].cost = (receivedRoutes[i].cost + 1 < MAX_COST) ? receivedRoutes[i].cost + 1 : MAX_COST;
                            routingTable[j].ttl = DV_TTL;
                            //dbg(ROUTING_CHANNEL, "Update to route: %d from neighbor: %d with new cost %d\n", routingTable[i].dest, routingTable[i].nextHop, routingTable[i].cost);
                        } else if(receivedRoutes[i].cost + 1 < MAX_COST && receivedRoutes[i].cost + 1 < routingTable[j].cost) {
                            routingTable[j].nextHop = myMsg->src;
                            routingTable[j].cost = receivedRoutes[i].cost + 1;
                            routingTable[j].ttl = DV_TTL;
                            //dbg(ROUTING_CHANNEL, "More optimal route found to dest: %d through %d at cost %d\n", receivedRoutes[i].dest, receivedRoutes[i].nextHop, receivedRoutes[i].cost +1);
                        }
                    }
                    // If route is already present AND not unreachable -> update the TTL
                    if(routingTable[j].nextHop == receivedRoutes[i].nextHop && routingTable[j].cost == receivedRoutes[i].cost && routingTable[j].cost != MAX_COST) {
                        routingTable[j].ttl = DV_TTL;
                    }
                    routePresent = TRUE;
                    break;
                }
            }
            // If route not in table AND there is space AND it is not a split horizon packet AND the route cost is not infinite -> add it
            if(!routePresent && numRoutes != MAX_ROUTES && receivedRoutes[i].nextHop != 0 && receivedRoutes[i].cost != MAX_COST) {
                addRoute(receivedRoutes[i].dest, myMsg->src, receivedRoutes[i].cost + 1, DV_TTL);
                routesAdded = TRUE;
            }
            routePresent = FALSE;
        }
        if(routesAdded) {
            triggerUpdate();
        }
    }

    command void RoutingTable.handleNeighborLost(uint16_t lostNeighbor) {
        // Neighbor lost, update routing table and trigger DV update
        uint16_t i;
        if(lostNeighbor == 0)
            return;
        dbg(ROUTING_CHANNEL, "Neighbor discovery has lost neighbor %u. Distance is now infinite!\n", lostNeighbor);
        for(i = 1; i < numRoutes; i++) {
            if(routingTable[i].dest == lostNeighbor || routingTable[i].nextHop == lostNeighbor) {
                routingTable[i].cost = MAX_COST;
            }
        }
        triggerUpdate();
    }

    command void RoutingTable.handleNeighborFound() {
        // Neighbor found, update routing table and trigger DV update
        inputNeighbors();
    }


    command void RoutingTable.printRouteTable() {
        uint8_t i;
        dbg(ROUTING_CHANNEL, "DEST  HOP  COST  TTL\n");
        for(i = 0; i < numRoutes; i++) {
            dbg(ROUTING_CHANNEL, "%4d%5d%6d%5d\n", routingTable[i].dest, routingTable[i].nextHop, routingTable[i].cost, routingTable[i].ttl);
        }
    }

    void initilizeRoutingTable() {
        addRoute(TOS_NODE_ID, TOS_NODE_ID, 0, DV_TTL);
    }

    uint8_t findNextHop(uint8_t dest) {
        uint16_t i;
        for(i = 1; i < numRoutes; i++) {
            if(routingTable[i].dest == dest) {
                return (routingTable[i].cost == MAX_COST) ? 0 : routingTable[i].nextHop;
            }
        }
        return 0;
    }

    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost, uint8_t ttl) {
        // Add route to the end of the current list
        if(numRoutes != MAX_ROUTES) {
            routingTable[numRoutes].dest = dest;
            routingTable[numRoutes].nextHop = nextHop;
            routingTable[numRoutes].cost = cost;
            routingTable[numRoutes].ttl = ttl;
            numRoutes++;
        }
        //dbg(ROUTING_CHANNEL, "Added entry in routing table for node: %u\n", dest);
    }

    void removeRoute(uint8_t idx) {
        uint8_t j;
        // Move other entries left
        for(j = idx+1; j < numRoutes; j++) {
            routingTable[j-1].dest = routingTable[j].dest;
            routingTable[j-1].nextHop = routingTable[j].nextHop;
            routingTable[j-1].cost = routingTable[j].cost;
            routingTable[j-1].ttl = routingTable[j].ttl;
        }
        // Zero the j-1 entry
        routingTable[j-1].dest = 0;
        routingTable[j-1].nextHop = 0;
        routingTable[j-1].cost = MAX_COST;
        routingTable[j-1].ttl = 0;
        numRoutes--;        
    }

    void decrementTTLs() {
        uint8_t i;
        for(i = 1; i < numRoutes; i++) {
            // If valid entry in the routing table -> decrement the TTL
            if(routingTable[i].ttl != 0) {
                routingTable[i].ttl--;
            }
            // If TTL is zero -> remove the route
            if(routingTable[i].ttl == 0) {                
                dbg(ROUTING_CHANNEL, "Route stale, removing: %u\n", routingTable[i].dest);
                removeRoute(i);
                triggerUpdate();
            }
        }
    }

    bool inputNeighbors() {
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint8_t i, j;
        bool routeFound = FALSE, newNeighborfound = FALSE;
        for(i = 0; i < neighborsListSize; i++) {
            for(j = 1; j < numRoutes; j++) {
                // If neighbor found in routing table -> update table entry
                if(neighbors[i] == routingTable[j].dest) {
                    routingTable[j].nextHop = neighbors[i];
                    routingTable[j].cost = 1;
                    routingTable[j].ttl = DV_TTL;
                    routeFound = TRUE;
                    break;
                }
            }
            // If neighbor not already in the list and there is room -> add new neighbor
            if(!routeFound && numRoutes != MAX_ROUTES) {
                addRoute(neighbors[i], neighbors[i], 1, DV_TTL);                
                newNeighborfound = TRUE;
            } else if(numRoutes == MAX_ROUTES) {
                dbg(ROUTING_CHANNEL, "Routing table full. Cannot add entry for node: %u\n", neighbors[i]);
            }
            routeFound = FALSE;
        }
        if(newNeighborfound) {
            triggerUpdate();
            return TRUE;        
        }
        return FALSE;
    }

    // Skip the route for split horizon
    // Alter route table for poison reverse, keeping values in temp vars
    // Copy route onto array
    // Restore original route
    // Send packet with copy of partial routing table
    void triggerUpdate() {
        // Send routes to all neighbors one at a time. Use split horizon, poison reverse
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint8_t i = 0, j = 0, counter = 0;
        uint8_t temp;
        Route packetRoutes[5];
        bool isSwapped = FALSE;
        // Zero out the array
        for(i = 0; i < 5; i++) {
                packetRoutes[i].dest = 0;
                packetRoutes[i].nextHop = 0;
                packetRoutes[i].cost = 0;
                packetRoutes[i].ttl = 0;
        }
        // Send to every neighbor
        for(i = 0; i < neighborsListSize; i++) {
            while(j < numRoutes) {
                temp = routingTable[j].nextHop;
                routingTable[j].nextHop = 0;
                isSwapped = TRUE;
                
                // Add route to array to be sent out
                packetRoutes[counter].dest = routingTable[j].dest;
                packetRoutes[counter].nextHop = routingTable[j].nextHop;
                packetRoutes[counter].cost = routingTable[j].cost;
                counter++;
                // If our array is full or we have added all routes -> send out packet with routes
                if(counter == 5 || j == numRoutes-1) {
                    // Send out packet
                    makePack(&routePack, TOS_NODE_ID, neighbors[i], 1, PROTOCOL_DV, 0, &packetRoutes, sizeof(packetRoutes));
                    call Sender.send(routePack, neighbors[i]);
                    // Zero out array
                    while(counter > 0) {
                        counter--;
                        packetRoutes[counter].dest = 0;
                        packetRoutes[counter].nextHop = 0;
                        packetRoutes[counter].cost = 0;
                    }
                }
                // Restore the table
                routingTable[j].nextHop = temp;
                
                isSwapped = FALSE;
                j++;
            }
            j = 0;
        }
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }    

}