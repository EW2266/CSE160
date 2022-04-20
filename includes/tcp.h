#ifndef __TCP_H__
#define __TCP_H__

#include "protocol.h"
#include "channels.h"

#define NUM_SUPPORTED_PORTS 256
#define TCP_PACKET_PAYLOAD_LENGTH 5
#define TCP_PACKET_PAYLOAD_SIZE TCP_PACKET_PAYLOAD_LENGTH*sizeof(nx_uint16_t)
#define TCP_INITIAL_RTT 700
#define TCP_RTT_ALPHA 80

enum tcp_flags{
	DATA = 0,
    ACK = 1,
	SYN = 2,
	SYN_ACK = 3,
    FIN = 4,
    FIN_ACK = 5
};

typedef nx_struct tcp_pack {
	nx_uint8_t srcPort;
	nx_uint8_t destPort;
	nx_uint8_t seq;
	nx_uint8_t ack;
	nx_uint8_t flags;
	nx_uint8_t advertisedWindow;
	nx_uint8_t length;
	nx_uint16_t payload[TCP_PACKET_PAYLOAD_LENGTH];
} tcp_pack;


#endif