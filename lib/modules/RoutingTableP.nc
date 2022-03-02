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
    struct RoutingTableEntry RoutingTable[20]; //maximum of 20 nodes in a network
    struct neighbor neighbors[20];
    struct RoutingTableEntry initial;
    uint8_t neighborsize = 0;
    uint8_t tablesize = 0;
    uint16_t SEQ_NUM=200;
    //uint8_t *temp = &SEQ_NUM;
    pack sendPackage; 

    void printtable();
    void send_to_neighbors(RoutingTableEntry);
    void addtolist(Pack);
    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);


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
        initial.protocol = PROTOCOL_DV;
        initial.TTL = MAX_TTL;
        send_to_neighbors(initial);
    }

    event message_t *Receiver.receive(message_t * msg, void *payload, uint8_t len){
        if (len == sizeof(pack)){ //check if there's an actual packet
            pack *contents = (pack*) payload;
            if(contents -> protocol != PROTOCOL_DV){
                return msg;
            }
            addtolist(pack *contents);
            send_to_neighbors();
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

    void send_to_neighbors(RoutingTableEntry entry){
        uint16_t temp1;
        uint16_t temp2;
        call NeighborDiscovery.giveneighborlist(neighbors);
        neighborsize = call NeighborDiscovery.givesize();

        for(temp1 = 0; temp1 < neighborsize; temp1++){
            for(temp2 = 0; temp2 < tablesize; temp2++){
                dbg(ROUTING_CHANNEL, "Sending to Neighbor Node %u\n", neighbors[temp1].id);
                initial.next_hop = neighbors[temp1].id;
                
                makePack(&sendPackage, TOS_NODE_ID, neighbors[temp1].id, MAX_TTL, SEQ_NUM , PROTOCOL_DV, RoutingTableEntry[temp2], sizeof(entry));
                Sender.send(sendPackage, neighbors[temp1].id);
            }
            
        }
    }

    void addtolist(pack contents){
        RoutingTableEntry entry;
        entry = contents -> payload;
        RoutingTableEntry[tablesize] = entry;
        tablesize++;
    }

    void printtable(){
        
    }
}