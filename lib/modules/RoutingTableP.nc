#include "../../includes/RoutingTableEntry.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#define MAX_ROUTE_ENTRIES 20
#define MAX_COST 20

module RoutingTableP{

    provides interface RoutingTable;

    uses interface Timer<TMilli> as periodicTimer;
    uses interface Packet;
    uses interface AMPacket;
    //Uses SimpleSend interface to forward recieved packet as broadcast
    uses interface SimpleSend as Sender;
    //Uses the Receive interface to determine if received packet is meant for me.
	uses interface Receive as Receiver;

    uses interface NeighborDiscovery;
}

implementation {
    struct RoutingTableEntry Table[MAX_ROUTE_ENTRIES]; //maximum of 20 nodes in a network
    struct neighbor neighbors[20];
    uint8_t neighborsize = 0;
    uint8_t tablesize = 0;
    uint16_t SEQ_NUM=200;
    //uint8_t *temp = &SEQ_NUM;
    pack sendPackage; 


    void addroutetolist(uint8_t dest, uint8_t cost, uint8_t next_hop);
    void printtable();
    void update();
    //void addtolist(pack * contnets);
    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);

	bool inList(struct RoutingTableEntry entry){
		uint32_t index1;
		for(index1 = 0; index1 < tablesize; index1++){
            //dbg(ROUTING_CHANNEL, "%u vs. %u\n", Table[index1].dest, id);
			if(Table[index1].dest == entry.dest || Table[index1].next_hop == entry.next_hop){
				return TRUE;
			}
		}
		return FALSE;
	}

	event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len){
    	pack* myMsg= (pack*) payload;
    	if(len==sizeof(pack)){
        	//dbg(GENERAL_CHANNEL, "Packet Received protocol: %u\n", myMsg -> protocol);
        	if(myMsg->protocol == PROTOCOL_DV) {
            	//dbg(GENERAL_CHANNEL, "Got DV Protocol\n");
            	call RoutingTable.DVRouting(myMsg);
        	}
        	return msg;
	  	}  
      	dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      	return msg;
   	}

	command void RoutingTable.DVRouting(pack * contents){
		uint16_t temp1, temp2;
		bool routeexist = FALSE;
		bool routeadded = FALSE;
		struct RoutingTableEntry* templist = (struct RoutingTableEntry*) contents -> payload;

		//dbg(ROUTING_CHANNEL, "DVRouring called\n");
		
		for(temp1 = 0; temp1 < MAX_ROUTE_ENTRIES; temp1 ++){
			if(templist[temp1].dest == 0){
				//dbg(ROUTING_CHANNEL, "Reached bottom\n");
				break;
			}
			//dbg(ROUTING_CHANNEL, "Node %u, Dest: %u\n", TOS_NODE_ID, templist[temp1].dest);
			for(temp2 = 0; temp2 < tablesize; temp2++){
				if(templist[temp1].dest == Table[temp2].dest){
					if(templist[temp1].next_hop != 0){
						//dbg(ROUTING_CHANNEL, "templist[temp1].next_hop != 0\n");
						if(Table[temp2].next_hop == contents -> src){
							//dbg(ROUTING_CHANNEL, "Routing Packet - src: %u, dest: %u, seq: %u, next hop: %u, cost: %u\n", 
							//	contents -> src, templist[temp1].dest, contents -> seq, templist[temp1].next_hop, templist[temp1].cost);
							if(templist[temp1].cost + 1 <= MAX_COST){
								Table[temp2].cost = templist[temp1].cost + 1;
							}
							else{
								Table[temp2].cost = MAX_COST;
							}
						}
						else if(templist[temp1].cost + 1 < MAX_COST && templist[temp1].cost + 1 < Table[temp2].cost){
							Table[temp2].next_hop = contents -> src;
							Table[temp2].cost = templist[temp1].cost + 1;
							dbg(ROUTING_CHANNEL, "Better route found\n");
						}
					}
					if(templist[temp1].next_hop == Table[temp2].next_hop && templist[temp1].cost == Table[temp2].cost && templist[temp1].cost < MAX_COST){
						
					}
					//dbg(ROUTING_CHANNEL, "Route exist\n");
					routeexist = TRUE;
					break;
				}
			}
			if(!routeexist && tablesize <= MAX_ROUTE_ENTRIES && templist[temp1].next_hop != 0 && templist[temp1].cost < MAX_COST){
				addroutetolist(templist[temp1].dest, templist[temp1].cost + 1, contents -> src);
				routeadded = TRUE;
			}
			routeexist = FALSE;
		}
		if(routeadded == TRUE){
			//dbg(ROUTING_CHANNEL, "Route added\n");
				update();
		}
	}

	
	
    void initializelist(){ // adding itself to list
    	addroutetolist(TOS_NODE_ID, 0, TOS_NODE_ID);
    }

	bool putneighborsinlist(){
		uint16_t temp1;
		uint16_t temp2;
		bool foundroute = FALSE;
		bool foundnewneighbor = FALSE;
		
		//dbg(ROUTING_CHANNEL, "put neighbors inlist\n");
		call NeighborDiscovery.giveneighborlist(neighbors);
        neighborsize = call NeighborDiscovery.givesize();
        //dbg(ROUTING_CHANNEL, "Neighborsize: %u\n", neighborsize);
		
		for(temp1 = 0; temp1 < neighborsize; temp1++){
			for(temp2 = 1; temp2 < tablesize; temp2++){
				if(neighbors[temp1].id == Table[temp2].dest){ //check if neighbors are already in the list
                	Table[temp2].next_hop = neighbors[temp1].id;
					Table[temp2].cost = 1;
					foundroute = TRUE;
					break;
				}
            //dbg(ROUTING_CHANNEL, "Neighbor Node %u\n", neighbors[temp1].id);
			}
			if(foundroute == FALSE && tablesize != MAX_ROUTE_ENTRIES){ //if not in list and table not full
				//dbg(ROUTING_CHANNEL, "added new neighbors\n");
				addroutetolist(neighbors[temp1].id, 1, neighbors[temp1].id);
				foundnewneighbor = TRUE;
			}
			foundroute = FALSE;
		}
		if(foundnewneighbor){ //update after adding neighbors to the routing table
			//dbg(ROUTING_CHANNEL,"Found new neighbors\n");
			update();
			return TRUE;
		}
		return FALSE;
	}

    command void RoutingTable.print(){
        printtable();
    }

    command void RoutingTable.run(){
        //dbg(ROUTING_CHANNEL, "Starting Routing Table on Node %u\n", TOS_NODE_ID);
		initializelist();
        call periodicTimer.startPeriodic(8192);
    }

    event void periodicTimer.fired()
    {   
		update();
        if(putneighborsinlist() == FALSE){
			update();
		}
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

	void update(){ //send routing table to neighbors
		
		uint8_t i, j, k, temp;
		struct RoutingTableEntry Entry[5];
		bool check = FALSE;
		uint16_t listSize = call NeighborDiscovery.givesize();

		//dbg(ROUTING_CHANNEL, "Update\n");
        call NeighborDiscovery.giveneighborlist(neighbors);
		//dbg(ROUTING_CHANNEL, "Update\n");

		for(i = 0; i < 5; i++){
			Entry[i].dest = 0;
			Entry[i].next_hop = 0;
			Entry[i].cost = 0;
		}

		j = 0;
		k = 0;
		for(i = 0; i < listSize; i++){
			while(j < tablesize){
				if(neighbors[i].id == Table[j].next_hop){ 
					temp = Table[j].cost;
					Table[j].cost = MAX_COST;
					check = TRUE;
				}

				Entry[k].dest = Table[j].dest;
				Entry[k].next_hop = Table[j].next_hop;
				Entry[k].cost = Table[j].cost;
				k++;
				//dbg(ROUTING_CHANNEL, "Update\n");

				if(k == 5 || j == tablesize - 1){
					makePack(&sendPackage, TOS_NODE_ID, neighbors[i].id, MAX_TTL, 0, PROTOCOL_DV, (uint8_t*) Entry, sizeof(Entry)); 
					
					call Sender.send(sendPackage, neighbors[i].id);
					//dbg(ROUTING_CHANNEL, "Sent DV to Neighbor %u\n", neighbors[i].id);

						while(k > 0){
							k--;
							Entry[k].dest = 0;
							Entry[k].next_hop = 0;
							Entry[k].cost = 0;
						}
				}

				if(check == TRUE){
					Table[j].cost = temp;
				}
				check = FALSE;
				j++;
			}
			j=0;
		}
	}

	void addroutetolist(uint8_t dest, uint8_t cost, uint8_t next_hop){ //add routing table colum to list
    	if(tablesize <= MAX_ROUTE_ENTRIES){
			//dbg(ROUTING_CHANNEL,"Adding to list\n");
			Table[tablesize].dest = dest;
        	Table[tablesize].cost = cost;
        	Table[tablesize].next_hop = next_hop;
        	tablesize++;
			return;
    	}
		else{
			dbg(ROUTING_CHANNEL, "Max Route Entries");
		}
    }

    void printtable(){
        uint16_t temp;
        struct RoutingTableEntry tempentry;
        dbg(ROUTING_CHANNEL, "Routing Table:\n");
        dbg(ROUTING_CHANNEL, "Dest\tHop\tCount\n");
        for(temp = 0; temp < tablesize; temp++){
					dbg(ROUTING_CHANNEL, "%u\t\t%u\t%u\n",Table[temp].dest, Table[temp].next_hop, Table[temp].cost);
        }
    }
}