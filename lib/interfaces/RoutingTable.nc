#include "../../includes/routingTableEntry.h"

interface RoutingTable{
    command void print();
    command void run();
    command void DVRouting(pack * contents);
}