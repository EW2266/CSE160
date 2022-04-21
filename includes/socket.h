#ifndef __SOCKET_H__
#define __SOCKET_H__

#define TCP_APP_BUFFER_SIZE 1024
#define TCP_APP_READ_SIZE 10

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_type {
    SERVER,
    CLIENT
};

enum socket_state{
    CLOSED,
    OPENED,
    NAMED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
    FIN_WAIT_1,
    FIN_WAIT_2,
    CLOSING,
    TIME_WAIT,
    CLOSE_WAIT,
    LAST_ACK
};

typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
} socket_addr_t;

// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t {
    uint8_t flags;
    enum socket_state state;
    enum socket_type type;
    socket_addr_t src;
    socket_addr_t dest;
    uint8_t connectionQueue[MAX_NUM_OF_SOCKETS-1];
    uint8_t stopAndWait;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;
    uint8_t lastAck;
    uint8_t lastSent;

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;

    uint32_t RTT;
    uint32_t RTO;
    uint32_t RTX;
    uint8_t advertisedWindow;
}socket_store_t;

typedef struct server_t {
        uint8_t sockfd;
        uint8_t conns[MAX_NUM_OF_SOCKETS-1];
        uint8_t numConns;
        uint16_t bytesRead;
        uint16_t bytesWritten;
        uint8_t buffer[TCP_APP_BUFFER_SIZE];
    } server_t;

    typedef struct client_t {
        uint8_t sockfd;
        uint16_t bytesWritten;
        uint16_t bytesTransferred;
        uint16_t counter;
        uint16_t transfer;
        uint8_t buffer[TCP_APP_BUFFER_SIZE];
    } client_t;

#endif
