#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/RoutingTableEntry.h"

configuration RoutingTableC{
	provides interface RoutingTable;
}

implementation{
	components RoutingTableP;
	RoutingTable = RoutingTableP.RoutingTable;

	components new TimerMilliC() as periodicTimer;
    RoutingTableP.periodicTimer -> periodicTimer;

	components new SimpleSendC(AM_PACK) as SimpleSender;
    RoutingTableP.Sender -> SimpleSender;

	components new AMReceiverC(AM_PACK) as AMReceiver;
	RoutingTableP.Receiver -> AMReceiver;
	
	components NeighborDiscoveryC;
	RoutingTableP.NeighborDiscovery -> NeighborDiscoveryC;
}