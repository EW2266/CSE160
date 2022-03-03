#include "../../includes/RoutingTableEntry.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#define MAX_ROUTE_ENTRIES 20
#define MAX_COST 999


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
    struct RoutingTableEntry Table[20]; //maximum of 20 nodes in a network
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

	command void RoutingTable.send(uint16_t dest, uint8_t *payload) {
        makePack(&sendPackage, TOS_NODE_ID, dest, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %u TO %u\n", TOS_NODE_ID, dest);
        logPack(&sendPackage);
        call RoutingTable.routePacket(&sendPackage);
    }

    command uint16_t RoutingTable.getNextHop(uint16_t dest){
		uint32_t x;
		for(x = 0; x < tablesize; x++){
			if(Table[x].dest == dest && Table[x].cost == MAX_COST){
				return Table[x].next_hop;
			}
		}
		return 0;
	}

	command void RoutingTable.routePacket(pack *contents){
		
		uint8_t nexthop;
		//dbg(ROUTING_CHANNEL, "Dest: %u recieved by Node %u\n", contents -> dest, TOS_NODE_ID);
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
		
		if((nexthop = call RoutingTable.getNextHop(contents->dest))){
			dbg(ROUTING_CHANNEL, "Node %u packet passing through Node %u\n", TOS_NODE_ID, nexthop);
			call Sender.send(*contents, nexthop);
		}
		else {
            //dbg(ROUTING_CHANNEL, "No route to destination. Dropping packet...\n");
            //logPack(myMsg);
        }
	}



	command void RoutingTable.DVRouting(pack * contents){
		uint16_t temp1, temp2;
		bool routeexist = FALSE;
		bool routeadded = FALSE;
		struct RoutingTableEntry* templist = (struct RoutingTableEntry*) contents -> payload;

		//dbg(ROUTING_CHANNEL, "DVRouring called\n");
		
		for(temp1 = 0; temp1 < 5; temp1 ++){
			if(templist[temp1].dest == 0){
				//dbg(ROUTING_CHANNEL, "Reached bottom\n");
				break;
			}
			//dbg(ROUTING_CHANNEL, "Node %u, Dest: %u\n", TOS_NODE_ID, templist[temp1].dest);
			for(temp2 = 0; temp2 < tablesize; temp2++){
				
				if(templist[temp1].dest == Table[temp2].dest){
					
					if(templist[temp1].next_hop != 0){
						if(Table[temp2].next_hop == contents -> src){
							//dbg(ROUTING_CHANNEL, "Update cost\n");
							//if(inList(templist[temp1]) == TRUE){
								//dbg(ROUTING_CHANNEL, "Already in List\n");
								//continue;
							//}
							//dbg(ROUTING_CHANNEL, "Routing Packet - src: %u, dest: %u, seq: %u, next hop: %u, cost: %u\n", 
							//	contents -> src, templist[temp1].dest, contents -> seq, templist[temp1].next_hop, templist[temp1].cost);
							if(templist[temp1].cost + 1 < MAX_COST){
								Table[temp2].cost = templist[temp1].cost + 1;
							}
							else{
								Table[temp2].cost = MAX_COST;
							}
							
							//Table[temp2].cost = (templist[temp1].cost + 1 < MAX_COST) ? templist[temp1].cost + 1 : MAX_COST;
						}
						else if(templist[temp1].cost + 1 < MAX_COST && templist[temp1].cost + 1 < Table[temp2].cost){
							Table[temp2].next_hop = contents -> src;
							Table[temp2].cost = templist[temp1].cost + 1;
							dbg(ROUTING_CHANNEL, "Optimal route found\n");
						}
					}
					if(templist[temp1].next_hop == Table[temp2].next_hop && templist[temp1].cost == Table[temp2].cost && templist[temp1].cost < MAX_COST){
						
					}
					//dbg(ROUTING_CHANNEL, "Route exist\n");
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
			//dbg(ROUTING_CHANNEL, "Route added\n");
				update();
		}
	}

	
	
    void initializelist(){
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
				if(neighbors[temp1].id == Table[temp2].dest){
                	Table[temp2].next_hop = neighbors[temp1].id;
					Table[temp2].cost = 1;
					foundroute = TRUE;
					break;
				}
            //dbg(ROUTING_CHANNEL, "Neighbor Node %u\n", neighbors[temp1].id);
			}
			if(foundroute == FALSE && tablesize < MAX_ROUTE_ENTRIES){
				//dbg(ROUTING_CHANNEL, "added new neighbors\n");
				addroutetolist(neighbors[temp1].id, 1, neighbors[temp1].id);
				foundnewneighbor = TRUE;
			}
			foundroute = FALSE;
		}
		if(foundnewneighbor){
			//dbg(ROUTING_CHANNEL,"Found new neighbors\n");
			update();
			return TRUE;
		}
		return FALSE;
	}

    void addroutetolist(uint8_t dest, uint8_t cost, uint8_t next_hop){
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
			//dbg(ROUTING_CHANNEL,"Max route entries reached\n");
			return;
        }
        else{
            //dbg(ROUTING_CHANNEL, "Adding %u to list for Node %u\n", dest, TOS_NODE_ID);
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
        //dbg(ROUTING_CHANNEL, "Starting Routing Table on Node %u\n", TOS_NODE_ID);
        call periodicTimer.startPeriodic(512);
    }

	command void RoutingTable.lostNeighbor(uint16_t lost){
		uint16_t i;
		if(lost == 0){
			return;
		}
		dbg(ROUTING_CHANNEL, "A neighbor has been lost %u. Updating table...\n", lost);
		for(i = 1; i < tablesize; i++){
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

				if(k == 5 || j == tablesize-1){
					makePack(&sendPackage, TOS_NODE_ID, neighbors[i].id, 1, 0, PROTOCOL_DV, (uint8_t*) Entry, sizeof(Entry)); 
					
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


    void printtable(){
        uint16_t temp;
        struct RoutingTableEntry tempentry;
        dbg(ROUTING_CHANNEL, "Routing Table:\n");
        dbg(ROUTING_CHANNEL, "Dest\tHop\tCount\n");
        for(temp = 0; temp < tablesize; temp++){
            //if(tempentry.dest != 999){
                //dbg(ROUTING_CHANNEL, "Hi\n");
				if(Table[temp].dest != TOS_NODE_ID){
					dbg(ROUTING_CHANNEL, "%u\t\t%u\t%u\n",Table[temp].dest, Table[temp].next_hop, Table[temp].cost);
				}
            
            //}
        }
    }
}