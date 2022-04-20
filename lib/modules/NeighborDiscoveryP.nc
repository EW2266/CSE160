#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

#define ND_TTL  5

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as NeighborDiscoveryTimer;
    uses interface Random as Random;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint32_t> as NeighborMap;
    uses interface RoutingTable as RoutingTable;
}

implementation {
    pack sendPackage;
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    command error_t NeighborDiscovery.start() {
        call NeighborDiscoveryTimer.startPeriodic(10000 + (uint16_t) (call Random.rand16()%1000));
        dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery Started on node %u!\n", TOS_NODE_ID);
        return SUCCESS;
    }

    command void NeighborDiscovery.handleNeighbor(pack* myMsg) {
        // Neighbor Discovery packet received
        if(myMsg->protocol == PROTOCOL_PING && myMsg->TTL > 0) {
            myMsg->TTL -= 1;
            myMsg->src = TOS_NODE_ID;
            myMsg->protocol = PROTOCOL_PINGREPLY;
            call Sender.send(*myMsg, AM_BROADCAST_ADDR);
            dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery PING!\n");
        } else if(myMsg->protocol == PROTOCOL_PINGREPLY && myMsg->dest == 0) {
            dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery PINGREPLY! Found Neighbor %d\n", myMsg->src);
            if(!call NeighborMap.contains(myMsg->src)) {
                call NeighborMap.insert(myMsg->src, ND_TTL);
                call RoutingTable.handleNeighborFound();
                //call LinkStateRouting.handleNeighborFound();
            } else {
                call NeighborMap.insert(myMsg->src, ND_TTL);
            }
        }
    }

    event void NeighborDiscoveryTimer.fired() {
        uint16_t i = 0;
        uint8_t payload = 0;
        uint32_t* keys = call NeighborMap.getKeys();
        call NeighborDiscovery.printNeighbors();
        // Remove old neighbors
        for(; i < call NeighborMap.size(); i++) {
            if(keys[i] == 0) {
                continue;
            }
            if(call NeighborMap.get(keys[i]) == 0) {
                dbg(NEIGHBOR_CHANNEL, "Removing Neighbor %d\n", keys[i]);
                call RoutingTable.handleNeighborLost(keys[i]);
                //call LinkStateRouting.handleNeighborLost(keys[i]);
                call NeighborMap.remove(keys[i]);
            } else {
                call NeighborMap.insert(keys[i], call NeighborMap.get(keys[i])-1);
            }
        }
        // Send out a new neighbor discovery ping
        makePack(&sendPackage, TOS_NODE_ID, 0, 1, PROTOCOL_PING, 0, &payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    command void NeighborDiscovery.printNeighbors() {
        uint16_t i = 0;
        uint32_t* keys = call NeighborMap.getKeys();    
        // Print neighbors
        dbg(NEIGHBOR_CHANNEL, "Printing Neighbors:\n");
        for(; i < call NeighborMap.size(); i++) {
            if(keys[i] != 0) {
                dbg(NEIGHBOR_CHANNEL, "\tNeighbor: %d\n", keys[i]);
            }
        }
    }

    command uint32_t* NeighborDiscovery.getNeighbors() {
        return call NeighborMap.getKeys();
    }

    command uint16_t NeighborDiscovery.getNeighborListSize() {
        return call NeighborMap.size();
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
}