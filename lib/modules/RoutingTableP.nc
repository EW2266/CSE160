#include "../../includes/RoutingTableEntry.h"

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
    uint8_t neighborsize = 0;
    uint8_t tablesize = 0;
    uint16_t SEQ_NUM=200;
    uint8_t *temp = &SEQ_NUM;
    pack sendPackage; 

    void printtable();
    void send_to_neighbors();
    void maketable();
    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);


    command void RoutingTable.print(){
        printtable();
    }

    command void RoutingTable.run(){
        call periodicTimer.startPeriodic(512);
        send_to_neighbors();
    }

    event void periodicTimer.fired()
    {   
        dbg(ROUTING_CHANNEL, "Starting Routing Table\n");
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, SEQ_NUM , PROTOCOL_PING, temp , PACKET_MAX_PAYLOAD_SIZE);
		call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    event message_t *Receiver.receive(message_t * msg, void *payload, uint8_t len){

    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    void send_to_neighbors(){
        uint16_t temp1;

        call NeighborDiscovery.giveneighborlist(neighbors);
        neighborsize = call NeighborDiscovery.givesize();

        for(temp1 = 0; temp1 < neighborsize; temp1++){
            dbg(ROUTING_CHANNEL, "Sending to Neighbor Nodes\n");
        }
    }
}