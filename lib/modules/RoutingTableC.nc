/**
 * This class provides the Distance Vector Routing functionality for nodes on the network.
 *
 * @author Chris DeSoto
 * @date   2013/09/30
 *
 */

#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration RoutingTableC {
    provides interface RoutingTable;
}

implementation {
    components RoutingTableP;
    RoutingTable = RoutingTableP;

    components new SimpleSendC(AM_PACK);
    RoutingTableP.Sender -> SimpleSendC;

    components NeighborDiscoveryC;
    RoutingTableP.NeighborDiscovery -> NeighborDiscoveryC;

    components new TimerMilliC() as DVRTimer;
    RoutingTableP.DVRTimer -> DVRTimer;

    components RandomC as Random;
    RoutingTableP.Random -> Random;

    components TransportC as Transport;
    RoutingTableP.Transport -> Transport;
}
