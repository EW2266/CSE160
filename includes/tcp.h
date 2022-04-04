#ifndef TCP_H
#define TCP_H

#define NUM_SUPPORTED_PORTS 256
#define DEFAULT_RTT 700
#define TCP_RTT_ALPHA 80
#define TCP_PAYLOAD_LENGTH 5
#define TCP_PAYLOAD_SIZE TCP_PAYLOAD_LENGTH*sizeof(nx_uint16_t)

enum flags{
    DATA = 0,
    ACK = 1,
	SYN = 2,
	SYN_ACK = 3,
    FIN = 4,
    FIN_ACK = 5
};

typedef struct tcp{
    uint16_t srcport;
    uint16_t destport;
    uint16_t seqNUM;
    uint16_t ackNUM;
    uint16_t hdrLen;
    enum flags flag;
    uint16_t adwin;
    
    uint8_t payload[16];
};

#endif