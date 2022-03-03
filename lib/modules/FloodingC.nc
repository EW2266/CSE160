
configuration FloodingC{
	provides interface Flooding;
}

implementation{
	components FloodingP;
	Flooding = FloodingP.Flooding;

	components new SimpleSendC(AM_PACK) as SimpleSender;
	FloodingP.Sender -> SimpleSender;
	
	components new AMReceiverC(AM_PACK) as AMReceiver;
	FloodingP.Receiver -> AMReceiver;

	components new ListC(pack, 20) as KnownPacketsList;//max 20 packets stored
	FloodingP.KnownPacketsList -> KnownPacketsList;

	components NeighborDiscoveryC;
    FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
}