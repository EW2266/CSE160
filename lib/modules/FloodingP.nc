

#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
module FloodingP {
    provides interface Flooding;
    
    uses interface SimpleSend as Sender;
    uses interface MapList<uint16_t, uint16_t> as PacketsReceived;
}

implementation {
    pack sendPackage;
    uint16_t sequenceNum = 0;
    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    void handlePayloadReceived(pack *myMsg);
    void handleForward(pack* myMsg);

    command void Flooding.ping(uint16_t destination, uint8_t *payload) {
        dbg(FLOODING_CHANNEL, "PING EVENT \n");
        dbg(FLOODING_CHANNEL, "SENDER %d\n", TOS_NODE_ID);
        dbg(FLOODING_CHANNEL, "DEST %d\n", destination);
        makePack(&sendPackage, TOS_NODE_ID, destination, 22, PROTOCOL_PING, sequenceNum, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        sequenceNum++;
    }

    command void Flooding.handleFlooding(pack* myMsg) {
        if(call PacketsReceived.containsVal(myMsg->src, myMsg->seq)) {
            dbg(FLOODING_CHANNEL, "Packet seen already. Dropping...\n");
        } else if(myMsg->TTL == 0) {
            dbg(FLOODING_CHANNEL, "TTL expired...\n");
        } else if(myMsg->dest == TOS_NODE_ID) {
            handlePayloadReceived(myMsg);
        } else {
            handleForward(myMsg);
        }
    }

    command void Flooding.floodLSP(pack* myMsg) {
        myMsg->seq = sequenceNum++;
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    void handlePayloadReceived(pack *myMsg) {
        if(myMsg->protocol == PROTOCOL_PING) {
            dbg(FLOODING_CHANNEL, "Ping received!\n");
            logPack(myMsg);
            call PacketsReceived.insertVal(myMsg->src, myMsg->seq);
            makePack(&sendPackage, myMsg->dest, myMsg->src, BETTER_TTL, PROTOCOL_PINGREPLY, sequenceNum++,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
            dbg(FLOODING_CHANNEL, "Pingreply Sent!\n");
        } else if(myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(FLOODING_CHANNEL, "Pingreply received!\n");
            logPack(myMsg);
            call PacketsReceived.insertVal(myMsg->src, myMsg->seq);
        }
    }

    void handleForward(pack* myMsg) {
        myMsg->TTL -= 1;
        call PacketsReceived.insertVal(myMsg->src, myMsg->seq);
        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
        dbg(FLOODING_CHANNEL, "Packet forwarded with new TTL and logged...\n");
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