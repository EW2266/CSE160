#include "../../includes/RoutingTableEntry.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/DVR.h"
#define MAX_ROUTE_ENTRIES 20
#define MAX_COST 999

//#define STRATEGY 1
// change the names later 

module RoutingTableP{

    provides interface RoutingTable;

    uses interface Timer<TMilli> as periodicTimer;
    uses interface Packet;
    uses interface AMPacket;
    //Uses SimpleSend interface to forward recieved packet as broadcast
    uses interface SimpleSend as Sender;
    //Uses the Receive interface to determine if received packet is meant for me.
	//uses interface Receive as Receiver;

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
    void sendTable();
    void update();
    //void addtolist(pack * contnets);
    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);

	uint32_t inList(uint16_t id){
		uint32_t index1;
		for(index1 = 0; index1 < tablesize; index1++){
            //dbg(ROUTING_CHANNEL, "%u vs. %u\n", Table[index1].dest, id);
			if(Table[index1].dest == id){
				return index1;
			}
		}
		return 999;
	}

    command uint16_t RoutingTable.getNextHop(uint16_t dest){
        uint32_t x;
        dbg(ROUTING_CHANNEL, "get next hop called\n");
		
		for(x = 0; x < tablesize; x++){
			if(Table[x].dest == dest && Table[x].cost == MAX_COST){
				return Table[x].next_hop;
			}
		}
		return 0;
	}

	command void RoutingTable.send(uint16_t dest, uint8_t *payload) {
        dbg(ROUTING_CHANNEL, "send called\n");
        makePack(&sendPackage, TOS_NODE_ID, dest, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %u TO %u\n", TOS_NODE_ID, dest);
        logPack(&sendPackage);
        call RoutingTable.routePacket(&sendPackage);
    }

	command void RoutingTable.routePacket(pack *contents){
        uint8_t nexthop;
        dbg(ROUTING_CHANNEL, "route packet\n");
		
		if(contents -> dest == TOS_NODE_ID && contents -> protocol == PROTOCOL_PING){
			makePack(&sendPackage, contents -> dest, contents -> src, 0, PROTOCOL_PINGREPLY, 0, (uint8_t*) contents -> payload, PACKET_MAX_PAYLOAD_SIZE);
			dbg(ROUTING_CHANNEL, "PING SIGNAL RECIEVED\n");
			call RoutingTable.routePacket(&sendPackage);
			return;
		}
		else if(contents -> dest == TOS_NODE_ID && contents -> protocol == PROTOCOL_PINGREPLY){
			dbg(ROUTING_CHANNEL, "PINGREPLY SIGNAL RECIEVED\n");
			return;
		}
		
		if(call RoutingTable.getNextHop(contents -> dest) != 0){
			nexthop = call RoutingTable.getNextHop(contents -> dest);
			dbg(ROUTING_CHANNEL, "%u packet passing through %u", TOS_NODE_ID, nexthop);
			call Sender.send(*contents, nexthop);
		}
	}

	command void RoutingTable.DVRouting(pack * contents){
        
		uint16_t temp1, temp2;
        struct RoutingTableEntry* templist;

		bool routeexist = FALSE;
		bool routeadded = FALSE;
        
		templist = (struct RoutingTableEntry*) contents -> payload;

        dbg(ROUTING_CHANNEL, "DVrouting called\n");
		for(temp1 = 0; temp1 < 5; temp1 ++){
			if(templist[temp1].dest == 0){
				break;
			}
			for(temp2 = 0; temp2 < tablesize; temp2++){
				if(templist[temp1].dest == Table[temp2].dest){
					if(templist[temp1].next_hop != 0){
						if(Table[temp2].next_hop == contents -> src){
							if(templist[temp1].cost + 1 < MAX_COST){
								templist[temp1].cost ++;
							}
							else{
								templist[temp1].cost = MAX_COST;
							}
						}
						else if(templist[temp1].cost + 1 < MAX_COST && templist[temp1].cost + 1 < Table[temp2].cost){
							Table[temp2].next_hop = contents -> src;
							Table[temp2].cost = templist[temp1].cost + 1;
						}
					}
					if(templist[temp1].next_hop == Table[temp2].next_hop && templist[temp1].cost == Table[temp2].cost && templist[temp1].cost != MAX_COST){
						
					}
					routeexist = TRUE;
					break;
				}
			}
			if(!routeexist && tablesize != MAX_ROUTE_ENTRIES && templist[temp1].next_hop != 0 && templist[temp1].cost != MAX_COST){
				addroutetolist(templist[temp1].dest, templist[temp1].cost + 1, contents -> src);
				routeadded = TRUE;
			}
			routeexist = FALSE;
		}
		if(routeadded == TRUE){
				update();
		}
	}


	
    void initializelist(){
        dbg(ROUTING_CHANNEL, "initialized\n");
    	addroutetolist(TOS_NODE_ID, 0, TOS_NODE_ID);
    }

	bool putneighborsinlist(){
        
		uint16_t temp1;
		uint16_t temp2;
		bool foundroute = FALSE;
		bool foundnewneighbor = FALSE;
		
		call NeighborDiscovery.giveneighborlist(neighbors);
        neighborsize = call NeighborDiscovery.givesize();
        //dbg(ROUTING_CHANNEL, "Neighborsize: %u\n", neighborsize);
		dbg(ROUTING_CHANNEL, "puting neighbors in list\n");
		for(temp1 = 0; temp1 < neighborsize; temp1++){
			for(temp2 = 0; temp2 < tablesize; temp2++){
				if(neighbors[temp1].id == Table[temp2].dest){
                	Table[temp2].next_hop = neighbors[temp1].id;
					Table[temp2].cost = 1;
					foundroute = TRUE;
					break;
				}
            //dbg(ROUTING_CHANNEL, "Neighbor Node %u\n", neighbors[temp1].id);
			}
			if(foundroute == FALSE && tablesize < MAX_ROUTE_ENTRIES){
				addroutetolist(neighbors[temp1].id, 1, neighbors[temp1].id);
				foundnewneighbor = TRUE;
			}
			foundroute = FALSE;
		}
		if(foundnewneighbor){
			update();
			return TRUE;
		}
		return FALSE;
	}

    void addroutetolist(uint8_t dest, uint8_t cost, uint8_t next_hop){
        dbg(ROUTING_CHANNEL, "adding route to list\n");
        //struct RoutingTableEntry entry;
        /*
        if(tablesize <= 20 && dest != TOS_NODE_ID && dest != 200){
            dbg(ROUTING_CHANNEL, "Adding %u to list\n", dest);
            entry.dest = dest;
            entry.cost = cost;
            entry.next_hop = next_hop;
            //entry.TTL = ttl;
            Table[tablesize] = entry;
            tablesize++;
        }
        */
        if(tablesize >= MAX_ROUTE_ENTRIES){
			return;
        }
        else{
            dbg(ROUTING_CHANNEL, "Adding %u to list\n", dest);
            //entry.dest = dest;
            //entry.cost = cost;
            //entry.next_hop = next_hop;
            //entry.TTL = ttl;
            Table[tablesize].dest = dest;
            Table[tablesize].cost = cost;
            Table[tablesize].next_hop = next_hop;
            tablesize++;
        }

    }

	void removeroute(uint8_t nodeid){
		uint8_t temp1;
		for(temp1 = nodeid + 1; temp1 < tablesize; temp1 ++){
			Table[temp1 - 1].dest = Table[temp1].dest;
			Table[temp1 - 1].next_hop = Table[temp1].next_hop;
			Table[temp1 - 1].cost = Table[temp1].cost;
		}

		Table[temp1 - 1].dest = 0;
		Table[temp1 - 1].next_hop = 0;
		Table[temp1 - 1].cost = MAX_COST;
		tablesize --;
	}

    command void RoutingTable.print(){
        printtable();
    }

    command void RoutingTable.run(){
        dbg(ROUTING_CHANNEL, "Starting Routing Table\n");
        call periodicTimer.startPeriodic(512);
    }


	command void RoutingTable.lostNeighbor(uint16_t lost){
		uint16_t i;
		if(lost == 0){
			return;
		}
		dbg(ROUTING_CHANNEL, "A neighbor has been lost %u. Updating table...\n", lost);
		for( i = 1; i < tablesize; i++){
			if(Table[i].dest == lost || Table[i].next_hop == lost){
				Table[i].cost == MAX_COST;
			}
		}
		update();
	}

    event void periodicTimer.fired()
    {   
        //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, SEQ_NUM , PROTOCOL_CMD, temp , PACKET_MAX_PAYLOAD_SIZE);
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        //initial.src = TOS_NODE_ID;
        //initial.seq = SEQ_NUM;
        //initial.protocol = PROTOCOL_DV;
        //initial.TTL = MAX_TTL;
        //send_to_neighbors(initial);
        //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, SEQ_NUM , PROTOCOL_NAME, temp , PACKET_MAX_PAYLOAD_SIZE);
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        //addroutetolist(TOS_NODE_ID, 0, TOS_NODE_ID, MAX_TTL);
        initializelist();
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

    void sendTable(){
        uint16_t temp1;
        uint16_t temp2;
        uint8_t* temppayload;
		struct RoutingTableEntry *entry;
        for(temp1 = 0; temp1 < tablesize; temp1++){
			if(Table[temp1].cost == 999){
				Table[temp1].next_hop = 999;
			}
		}
		//for(temp1 = 0; temp1 < neighborsize; temp1++){
			for(temp2 = 0; temp2 < tablesize; temp2++){
            	//dbg(ROUTING_CHANNEL, "Sending to Neighbor Node %u\n", neighbors[temp1].id);
            	//initial.next_hop = neighbors[temp1].id;
				if(Table[temp2].next_hop == Table[temp2].dest && Table[temp2].next_hop != 999){
					*entry = Table[temp2];
                    temppayload = (uint8_t*) entry;
					makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, 0 , PROTOCOL_PING, temppayload, sizeof(entry));
            		call Sender.send(sendPackage, sendPackage.dest);
				}
            	
        	}
		//}
        
            
        
    }

	void update(){
		//uint32_t* neighbors;
		uint16_t listSize = call NeighborDiscovery.givesize();
		uint8_t i, j, k, temp;
		struct RoutingTableEntry Entry[5];
		bool check = FALSE;

        call NeighborDiscovery.giveneighborlist(neighbors);
		for(i = 0; i < 5; i++){
			Entry[i].dest = 0;
			Entry[i].next_hop = 0;
			Entry[i].cost = 0;
		}
		for(i = 0; i < listSize; i++){
			while(j < tablesize){
                /*
				if((neighbors[i] == Table[j].next_hop) && (STRATEGY == SPLIT_HORIZON)){ 
					temp = Table[j].next_hop;
					Table[j].next_hop = 0;
					check = TRUE;
				}else 
                */
                if((neighbors[i].id == Table[j].next_hop)){
					temp = Table[j].cost;
					Table[j].cost = MAX_COST;
					check = TRUE;
				}

				Entry[k].dest = Table[j].dest;
				Entry[k].next_hop = Table[j].next_hop;
				Entry[k].cost = Table[j].cost;
				k++;

				if(k == 5 || j == tablesize-1){
					makePack(&sendPackage, TOS_NODE_ID, neighbors[i].id, 1, PROTOCOL_DV, 0, (uint8_t*) Entry, sizeof(Entry)); 
					call Sender.send(sendPackage, neighbors[i].id);

						while(k > 0){
							k--;
							Entry[k].dest = 0;
							Entry[k].next_hop = 0;
							Entry[k].cost = 0;
						}
				}
                /*
				if(check && STRATEGY == SPLIT_HORIZON){
					Table[j].next_hop = temp;
				}else 
                */
                if(check){
					Table[j].cost = temp;
				}
				check = FALSE;
				j++;
			}
			j=0;
		}
	}


    void printtable(){
        uint16_t temp;
        struct RoutingTableEntry tempentry;
        dbg(ROUTING_CHANNEL, "Routing Table:\n");
        dbg(ROUTING_CHANNEL, "Dest\tHop\tCount\n");
        for(temp = 0; temp < tablesize; temp++){
            tempentry = Table[temp];
            //if(tempentry.dest != 999){
                //dbg(ROUTING_CHANNEL, "Hi\n");
            dbg(ROUTING_CHANNEL, "%u\t\t%u\t%u\n",tempentry.dest, tempentry.next_hop, tempentry.cost);
            //}
        }
    }
}