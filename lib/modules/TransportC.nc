#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../includes/packet.h"
#include "../includes/socket.h"

configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components new SimpleSendC(AM_PACK);
    TransportP.Sender -> SimpleSendC;

    components NeighborDiscoveryC;
    TransportP.NeighborDiscovery -> NeighborDiscoveryC;

    components RoutingTableC;
    TransportP.RoutingTable -> RoutingTableC;

    components new TimerMilliC() as PeriodicTimer;
    TransportP.PeriodicTimer -> PeriodicTimer;

    components new HashmapC(uint8_t, 20);
    TransportP.HashMap -> HashmapC;
}