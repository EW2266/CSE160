#include "../../includes/neighbor.h"

interface NeighborDiscovery{
    command void run();
    command void print();
    command void giveneighborlist(struct neighbor* list);
    command uint16_t givesize();
}