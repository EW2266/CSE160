#include "../../includes/RoutingTableEntry.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

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
    struct RoutingTableEntry Table[20]; //maximum of 20 nodes in a network
    struct neighbor neighbors[20];
    struct RoutingTableEntry initial;
    uint8_t neighborsize = 0;
    uint8_t tablesize = 0;
    uint16_t SEQ_NUM=200;
    //uint8_t *temp = &SEQ_NUM;
    pack sendPackage; 

    void printtable();
    void send_to_neighbors(struct RoutingTableEntry);
    //void addtolist(pack * contnets);
    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);

    void addtolist(pack *contents){
        struct RoutingTableEntry entry;
        //entry = contents -> payload;
        Table[tablesize] = entry;
        tablesize++;
    }

    command void RoutingTable.print(){
        printtable();
    }

    command void RoutingTable.run(){
        call periodicTimer.startPeriodic(512);
    }

    event void periodicTimer.fired()
    {   
        dbg(ROUTING_CHANNEL, "Starting Routing Table\n");
        //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, SEQ_NUM , PROTOCOL_CMD, temp , PACKET_MAX_PAYLOAD_SIZE);
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        initial.src = TOS_NODE_ID;
        initial.seq = SEQ_NUM;
        //initial.protocol = PROTOCOL_DV;
        //initial.TTL = MAX_TTL;
        send_to_neighbors(initial);
    }

    event message_t *Receiver.receive(message_t * msg, void *payload, uint8_t len){
        uint8_t calccost;
        if (len == sizeof(pack)){ //check if there's an actual packet
            pack *contents = (pack*) payload;
            if(contents -> protocol != PROTOCOL_DV){
                return msg;
            }
            //dbg(ROUTING_CHANNEL, "Routing Packet - src: %u, dest: %u, seq: %u, next hop: %u, cost: %u\n", contents -> src, contents -> dest, contents -> seq, contents -> next_hop, contetns -> cost);
            //addtolist(*contents);
            //send_to_neighbors();
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

    void send_to_neighbors(struct RoutingTableEntry entry){
        uint16_t temp1;
        uint16_t temp2;
        call NeighborDiscovery.giveneighborlist(neighbors);
        neighborsize = call NeighborDiscovery.givesize();

        for(temp1 = 0; temp1 < neighborsize; temp1++){
            for(temp2 = 0; temp2 < tablesize; temp2++){
                dbg(ROUTING_CHANNEL, "Sending to Neighbor Node %u\n", neighbors[temp1].id);
                initial.next_hop = neighbors[temp1].id;
                
                //makePack(&sendPackage, TOS_NODE_ID, neighbors[temp1].id, MAX_TTL, SEQ_NUM , PROTOCOL_DV, Table[temp2], sizeof(entry));
                call Sender.send(sendPackage, neighbors[temp1].id);
            }
            
        }
    }


    void printtable(){
        uint16_t temp;
        struct RoutingTableEntry tempentry;
        dbg(ROUTING_CHANNEL, "Routing Table:\n");
        dbg(ROUTING_CHANNEL, "Dest \t Hop \t Count\n");
        for(temp = 0; temp < tablesize; temp++){
            tempentry = Table[temp];
            if(tempentry.src != 0){
                dbg(ROUTING_CHANNEL, "%u \t %u \t %u\n",tempentry.src, tempentry.next_hop, tempentry.cost);
            }
        }
    }
}