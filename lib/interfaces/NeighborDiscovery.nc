#include "../../includes/packet.h"

interface NeighborDiscovery {
   command error_t start();
   command void handleNeighbor(pack* myMsg);
   command void printNeighbors();
   command uint32_t* getNeighbors();
   command uint16_t getNeighborListSize();
}