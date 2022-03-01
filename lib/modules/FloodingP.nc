#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/neighbor.h"

module FloodingP
{
	//Provides the SimpleSend interface in order to flood packets
	provides interface Flooding;
	//Uses the SimpleSend interface to forward recieved packet as broadcast
	uses interface SimpleSend as Sender;
	//Uses the Receive interface to determine if received packet is meant for me.
	uses interface Receive as Receiver;

	uses interface Packet;
    uses interface AMPacket;
	//Uses the Queue interface to determine if packet recieved has been seen before
	uses interface List<pack> as KnownPacketsList;

	uses interface NeighborDiscovery;
}

implementation
{
	pack sendPackage;
	struct neighbor neighbors[20]; //Maximum of 20 neighbors?


	// Prototypes
	void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);
	bool isInList(pack packet);
	error_t addToList(pack packet);

	//Broadcast packet
	command error_t Flooding.send(pack msg, uint16_t dest)
	{
		//Attempt to send the packet
		
		uint16_t tempdest;
		uint16_t temp;
		uint16_t size;
		msg.TTL = MAX_TTL;
		//call NeighborDiscovery.run();
		//dbg(FLOODING_CHANNEL, "Sending from Flooding\n");
		call NeighborDiscovery.giveneighborlist(neighbors);
		size = call NeighborDiscovery.givesize();
		for(temp = 0; temp < size; temp ++){
			tempdest = neighbors[temp].id;
			if (call Sender.send(msg, tempdest) == SUCCESS){
				dbg(FLOODING_CHANNEL, "Initial Send.\n");
				return SUCCESS;
			}//send to neighbors
		}
		return FAIL;
	}

	//Event signaled when a node recieves a packet
	event message_t *Receiver.receive(message_t * msg, void *payload, uint8_t len)
	{
		//dbg(FLOODING_CHANNEL, "Packet Received in Flooding\n");
		uint16_t temp;
		uint16_t size;
		uint16_t tempdest;

		if (len == sizeof(pack))
		{
			pack *contents = (pack *)payload;
			//call NeighborDiscovery.run();
			//dbg(FLOODING_CHANNEL, "size of neighbor: %u\n", size);
			//dbg(FLOODING_CHANNEL, "First Neightbor: %u\n", neighbors[0].id);
			//If I am the original sender and have seen the packet before, drop it
			if ((contents->src == TOS_NODE_ID) || isInList(*contents))
			{
				//dbg(FLOODING_CHANNEL, "Dropping packet.\n");
				return msg;
			}
			//Kill the packet if TTL is 0
			if (contents->TTL == 0){
            //do nothing
            dbg(FLOODING_CHANNEL, "TTL: %d\n", contents-> TTL);
            return msg;
			}
            // to be continued by you ...
			call NeighborDiscovery.giveneighborlist(neighbors);
			size = call NeighborDiscovery.givesize();
			dbg(FLOODING_CHANNEL, "Receieved from Node %u\n", contents -> src);
			addToList(*contents);
			//after adding it to list, send it to other nodes
			//dbg(FLOODING_CHANNEL, "Sending to: ");
			
			//contents -> src = TOS_NODE_ID;
			for(temp = 0; temp < size; temp ++){
				if(contents -> src != TOS_NODE_ID){
					call Sender.send(*contents, neighbors[temp].id);//send to neighbors
					//dbg(FLOODING_CHANNEL,"Sending to Neighbor Node %u\n", neighbors[temp].id);
				}
			}
			//dbg(FLOODING_CHANNEL,"\n");
			
		}
		else{
			dbg(FLOODING_CHANNEL, "Not A Packet.\n");
		}
	}

	error_t addToList(pack packet){
		uint16_t size = call KnownPacketsList.size();
		if(size < 20){
			call KnownPacketsList.pushback(packet);
		}
		return TRUE;
	}

	bool isInList(pack packet){
		uint16_t size = call KnownPacketsList.size();
		uint16_t temp;
		pack temppack;

		if(!(call KnownPacketsList.isEmpty())){
			for(temp = 0; temp < size; temp ++){
				temppack = call KnownPacketsList.get(temp);
				if(packet.src == temppack.src && packet.seq == temppack.seq){
					return TRUE;
				}
			}
		}
		return FALSE;
	}

	void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length){
		Package->src = src;
      	Package->dest = dest;
      	Package->TTL = TTL;
      	Package->seq = seq;
      	Package->protocol = protocol;
      	memcpy(Package->payload, payload, length);
	}

	void printList(){
		uint16_t size = call KnownPacketsList.size();
		uint16_t temp;
		pack temppack;
		for(temp = 0; temp < size; temp ++){
			temppack = call KnownPacketsList.get(temp);
			dbg(FLOODING_CHANNEL, "Contained Messages: %u \n", temppack.dest);
		}
	}
}