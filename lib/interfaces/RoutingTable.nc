#include "../../includes/routingTableEntry.h"

interface RoutingTable{
    command void print();
    command void run();
    command uint16_t getNextHop(uint16_t finalDest);
    command void send(uint16_t dest, uint8_t *payload);
    command void routePacket(pack *contents);
    command void DVRouting(pack * contents);
    command void lostNeighbor(uint16_t lost);
}