#ifndef TCP_H
#define TCP_H

enum flags{
    NS = 0;
    CWR = 1;
    ECE = 2;
    URG = 3;
    ACK = 4;
    PSH = 5;
    RST = 6;
    SYN = 7;
    FIN = 8;
}

typedef struct tcp{
    uint16_t srcport;
    uint16_t destport;
    uint16_t seqNUM;
    uint16_t ackNUM;
    uint16_t hdrLen;
    flags flag;
    uint16_t adwin;
    
    uint8_t payload[16];
};

#endif