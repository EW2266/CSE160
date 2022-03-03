#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/neighbor.h"
#include <Timer.h>

configuration NeighborDiscoveryC{
    provides interface NeighborDiscovery;
}

implementation{
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new SimpleSendC(AM_PACK) as SimpleSender;
    NeighborDiscoveryP.Sender -> SimpleSender;

    components new AMReceiverC(AM_PACK) as AMReceiver;
    NeighborDiscoveryP.Receiver -> AMReceiver;

    components new TimerMilliC() as periodicTimer;
    NeighborDiscoveryP.periodicTimer -> periodicTimer;

    //components new ListC(neighbor, 20) as Neighborhood;
    //NeighborDiscoveryP.Neighborhood -> Neighborhood;
    
}