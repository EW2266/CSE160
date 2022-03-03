#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/neighbor.h"

module NeighborDiscoveryP
{

    //Provides the SimpleSend interface in order to neighbor discover packets
    provides interface NeighborDiscovery;
    //Uses SimpleSend interface to forward recieved packet as broadcast
    uses interface SimpleSend as Sender;
    //Uses the Receive interface to determine if received packet is meant for me.
	uses interface Receive as Receiver;

	//uses interface CommandHandler;

    uses interface Packet;
    uses interface AMPacket;
	//Uses the Queue interface to determine if packet recieved has been seen before
	//uses interface List<neighbor> as Neighborhood;
    uses interface Timer<TMilli> as periodicTimer;
   
}


implementation
{
	/*
    typedef struct neighbor{
    	uint16_t TTL;
    	uint16_t seq;
	};
	*/

    pack sendPackage; 
    uint16_t SEQ_NUM=200;
    uint8_t *temp = &SEQ_NUM;
	uint8_t temp1 = 0;
	uint16_t maxsize = 20;

    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t * payload, uint8_t length);

	bool isNeighbor(uint8_t nodeid);
    error_t addNeighbor(uint8_t nodeid);
    void updateNeighbors();
	void printNeighborhood();

	struct neighbor neighbors[20]; //Maximum of 20 neighbors?
	uint8_t neighborsize = 0;


	
    command void NeighborDiscovery.run()
	{	
		//dbg(NEIGHBOR_CHANNEL, "Sending from NeighborDiscovery\n");
        //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, SEQ_NUM , PROTOCOL_PING, temp , PACKET_MAX_PAYLOAD_SIZE);
        //SEQ_NUM++;
        //call Sender.send(sendPackage, AM_BROADCAST_ADDR);

		for(temp1 = 0; temp1 < 20; temp1++){
			neighbors[temp1].id = -1;
		}
        call periodicTimer.startPeriodic(512);
	}

	command void NeighborDiscovery.print(){
		printNeighborhood();
	}

    event void periodicTimer.fired()
    {
        //dbg(NEIGHBOR_CHANNEL, "Sending from NeighborDiscovery\n");
        //updateNeighbors();

		

		//printNeighborhood();
		//cout << "test" <<endl;

        //optional - call a funsion to organize the list
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, SEQ_NUM , PROTOCOL_PING, temp , PACKET_MAX_PAYLOAD_SIZE);
		call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

	//event void CommandHandler.printNeighbors(){
		//printNeighborhood();
	//}

    event message_t *Receiver.receive(message_t * msg, void *payload, uint8_t len)
    {
		//dbg(NEIGHBOR_CHANNEL, "RECIEVED\n");
        if (len == sizeof(pack)) //check if there's an actual packet
        {
            pack *contents = (pack*) payload;
        	//dbg(NEIGHBOR_CHANNEL, "NeighborReciver Called, %d\n", contents -> protocol);

            if (PROTOCOL_PING == contents -> protocol) //got a message, not a reply
            {
                if (contents -> TTL == 0)
                {
                //if TTL == 0, node dies, do nothing
					//dbg(NEIGHBOR_CHANNEL, "PING, TTL = 0\n");
					return msg;
				}
				if(isNeighbor(contents -> src)){//if it is in list, do nothing
					//dbg(NEIGHBOR_CHANNEL, "PING, INLIST\n");
					return msg;
				}
				//send a reply to node
				contents -> dest = contents -> src;
				contents -> src = TOS_NODE_ID;
				contents -> protocol = PROTOCOL_PINGREPLY;
				//dbg(NEIGHBOR_CHANNEL, "PING, PEPLYING\n");
				call Sender.send(*contents, contents -> dest);
			}
			else if(PROTOCOL_PINGREPLY == contents -> protocol && contents -> seq == SEQ_NUM){ //when getting a reply from nodes
				if (contents -> TTL == 0)
                {
                 //if TTL == 0, packet dies, do nothing
				 	//dbg(NEIGHBOR_CHANNEL, "PINGREPLY TTL = 0\n");
					return msg;
				}
				if(isNeighbor(contents -> src)){//if it is in list, do nothing
					//dbg(NEIGHBOR_CHANNEL, "PINGREPLY INLIST\n");
				}
				else{
					addNeighbor(contents -> src);
					return msg;
				}
			}
			return msg;
		}
		else{
			//dbg(NEIGHBOR_CHANNEL, "not a packet\n");
			return msg;
		}
		return msg;
	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

	bool isNeighbor(uint8_t nodeid){	//checks if the node is in list

		struct neighbor newnode;

		if(neighborsize == 0){ //not in list, return false
			return FALSE;
		}
		
		for(temp1 = 0; temp1 < neighborsize; temp1++){ //search through the list, if found, return true
			newnode = neighbors[temp1];
			if(newnode.id == nodeid){
				return TRUE;
			}
		}
		return FALSE; //if not found in the previous for loop, return false
	}

	error_t addNeighbor(uint8_t nodeid){
		

		struct neighbor newnode;

		if(isNeighbor(nodeid)){	//if already in list, do nothing
			//dbg(NEIGHBOR_CHANNEL, "ADD INLIST\n");
			return FAIL;
		}

		newnode.id = nodeid;

		if(neighborsize == maxsize){//if full, don't add
			//dbg(NEIGHBOR_CHANNEL, "ADD List Full\n");
			return FAIL;
		}
		else{//if not full, add at end
			neighbors[neighborsize] = newnode;
			//dbg(NEIGHBOR_CHANNEL, "ADD Neighbor Added \n");
			//updateNeighbors();
			neighborsize ++;
			return SUCCESS;
		}
		return FAIL;
	}
	
	void printNeighborhood(){

		struct neighbor newnode;

		//dbg(NEIGHBOR_CHANNEL, "Start Print \n");
		dbg(NEIGHBOR_CHANNEL, "Node %u's Neighbors are: <\n", TOS_NODE_ID);
		for(temp1 = 0; temp1 < neighborsize; temp1++){
			newnode = neighbors[temp1];
			dbg(NEIGHBOR_CHANNEL, "Node %u \n", newnode.id);
			
		}
		dbg(NEIGHBOR_CHANNEL, ">\n");
	}

	void updateNeighbors(){

		//struct neighbor newnode;
	/*
		for(temp1 = 0; temp1 < neighborsize; temp1++){
			dbg(NEIGHBOR_CHANNEL, "List Updated\n");
			//neighbors[temp1].TTL -= 1;
			newnode = neighbors[temp1];
			if(newnode.TTL < 1 || newnode.TTL > MAX_TTL){
				neighbors[temp1].seq = 0;
				//neighbors[temp1].TTL = 0;
				neighborsize --;
			}
		}
	*/

		//dbg(NEIGHBOR_CHANNEL, "Updated, Current Neighbor Counts: %d\n", neighborsize);
	}

	command void NeighborDiscovery.giveneighborlist(struct neighbor* list){
		//dbg(GENERAL_CHANNEL, "Give neighbor list\n");
		for(temp1 = 0; temp1 < neighborsize; temp1 ++){
			list[temp1].id = neighbors[temp1].id;
		}
	}

	command uint16_t NeighborDiscovery.givesize(){
		//dbg(GENERAL_CHANNEL, "Give neighbor size, %u\n", neighborsize);
		return neighborsize;
	}
}
