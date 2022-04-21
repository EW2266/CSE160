#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"
#include "../../includes/socket.h"
#include "../../includes/tcp.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module TransportP{
    provides interface Transport;

    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Timer<TMilli> as TransmissionTimer;
    uses interface NeighborDiscovery;
    uses interface RoutingTable;
    uses interface Hashmap<uint8_t> as SocketMap;
    uses interface Timer<TMilli> as AppTimer;
    uses interface Hashmap<uint8_t> as ConnectionMap;
}

implementation{
    server_t server[MAX_NUM_OF_SOCKETS];
    client_t client[MAX_NUM_OF_SOCKETS];
    uint8_t numServers = 0;
    uint8_t numClients = 0;
    pack ipPack;
    tcp_pack tcpPack;
    bool ports[NUM_SUPPORTED_PORTS];
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    uint16_t getServerBOccupied(uint8_t idx);
    uint16_t getClientBOccupied(uint8_t idx);
    uint16_t getClientBufferAvailable(uint8_t idx);
    uint16_t min(uint16_t a, uint16_t b);

    /*
    * Helper functions
    */

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length) {
                      //  dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!MAKE PACK!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    uint16_t min(uint16_t a, uint16_t b) {
        if(a <= b)
            return a;
        else
            return b;
    }

    void addConn(uint8_t fd, uint8_t conn) {
        uint8_t i;
        //  dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ADD CONNECTION!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        for(i = 0; i < MAX_NUM_OF_SOCKETS-1; i++) {
            if(sockets[fd-1].connectionQueue[i] == 0) {
                sockets[fd-1].connectionQueue[i] = conn;
                break;
            }
        }
    }

    uint8_t getSocket(uint8_t src, uint8_t srcPort, uint8_t dest, uint8_t destPort) {
        uint32_t socketId = (((uint32_t)src) << 24) | (((uint32_t)srcPort) << 16) | (((uint32_t)dest) << 8) | (((uint32_t)destPort));
                    //    dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!GET SOCKET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        return call SocketMap.get(socketId);
    }

    uint16_t getRR(uint8_t fd) {
        uint16_t lastRead, nextExpected;

        lastRead = sockets[fd-1].lastRead % SOCKET_BUFFER_SIZE;
        nextExpected = sockets[fd-1].nextExpected % SOCKET_BUFFER_SIZE;
        if(lastRead < nextExpected)
            return nextExpected - lastRead - 1;        
        else
            return SOCKET_BUFFER_SIZE - lastRead + nextExpected - 1;        
    }

    uint16_t getSendBOccupied(uint8_t fd) {
        uint8_t lastSent, lastWritten;
        //  dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!GET SEND BUFFER OCCUPIED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        lastSent = sockets[fd-1].lastSent % SOCKET_BUFFER_SIZE;
        lastWritten = sockets[fd-1].lastWritten % SOCKET_BUFFER_SIZE;
        if(lastSent <= lastWritten)
            return lastWritten - lastSent;
        else
            return lastWritten + (SOCKET_BUFFER_SIZE - lastSent);
    }

    uint16_t getSendBAvailable(uint8_t fd) {
        uint8_t lastAck, lastWritten;

        lastAck = sockets[fd-1].lastAck % SOCKET_BUFFER_SIZE;
        lastWritten = sockets[fd-1].lastWritten % SOCKET_BUFFER_SIZE;
        if(lastAck == lastWritten)
            return SOCKET_BUFFER_SIZE - 1;
        else if(lastAck > lastWritten)
            return lastAck - lastWritten - 1;
        else
            return lastAck + (SOCKET_BUFFER_SIZE - lastWritten) - 1;
    }

    uint16_t getReceiveBAvailable(uint8_t fd) {
        uint8_t lastRead, lastRcvd;
        lastRead = sockets[fd-1].lastRead % SOCKET_BUFFER_SIZE;
        lastRcvd = sockets[fd-1].lastRcvd % SOCKET_BUFFER_SIZE;
                   //     dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!GET RECEIVE BUFFER AVAILABLE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(lastRead == lastRcvd)
            return SOCKET_BUFFER_SIZE - 1;
        else if(lastRead > lastRcvd)
            return lastRead - lastRcvd - 1;
        else
            return lastRead + (SOCKET_BUFFER_SIZE - lastRcvd) - 1;
    }

    uint8_t calcEW(uint8_t fd) {

        uint16_t lastAck, lastSent, temp;
        lastAck = sockets[fd-1].lastAck % SOCKET_BUFFER_SIZE;
        lastSent = sockets[fd-1].lastSent % SOCKET_BUFFER_SIZE;
        if(lastAck <= lastSent)
            temp = lastSent - lastAck;
        else
            temp = SOCKET_BUFFER_SIZE - lastAck + lastSent;

        return sockets[fd-1].advertisedWindow - temp;
    }

    uint8_t sendTCPPacket(uint8_t fd, uint8_t flags) {
        uint8_t length, bytes = 0;
        uint8_t* payload = (uint8_t*)tcpPack.payload;
        // Set up packet info
        //     dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!SEND TCP PACKET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        tcpPack.srcPort = sockets[fd-1].src.port;
        tcpPack.destPort = sockets[fd-1].dest.port;
        tcpPack.flags = flags;
        tcpPack.advertisedWindow = sockets[fd-1].advertisedWindow;
        tcpPack.ack = sockets[fd-1].nextExpected;
        // Send initial sequence number or next expected
        if(flags == SYN) {
            tcpPack.seq = sockets[fd-1].lastSent;
        } else {
            tcpPack.seq = sockets[fd-1].lastSent + 1;
        }
        if(flags == DATA) {
            // Choose the min of the effective window, the number of bytes available to send, and the max packet size
            length = min(calcEW(fd), min(getSendBOccupied(fd), TCP_PACKET_PAYLOAD_SIZE));
            length ^= length & 1;
            if(length == 0) {
                return 0;
            }
            while(bytes < length) {
                memcpy(payload+bytes, &sockets[fd-1].sendBuff[(++sockets[fd-1].lastSent) % SOCKET_BUFFER_SIZE], 1);
                bytes += 1;
            }
            tcpPack.length = length;
        }
        if(flags != ACK) {
            sockets[fd-1].RTX = call TransmissionTimer.getNow();
            sockets[fd-1].RTO = call TransmissionTimer.getNow() + (2 * sockets[fd-1].RTT);
        }
        makePack(&ipPack, TOS_NODE_ID, sockets[fd-1].dest.addr, BETTER_TTL, PROTOCOL_TCP, 0, &tcpPack, sizeof(tcp_pack));
        call RoutingTable.routePacket(&ipPack);
        return bytes;
    }

    void sendTheWindow(uint8_t fd) {
        uint16_t bytesRemaining = min(getSendBOccupied(fd), calcEW(fd));
        uint8_t bytesSent;

        while(bytesRemaining > 0 && bytesSent > 0) {
            bytesSent = sendTCPPacket(fd, DATA);
            bytesRemaining -= bytesSent;
        }
    }

    bool readInData(uint8_t fd, tcp_pack* tcp_rcvd) {
        uint16_t bytesRead = 0;
        uint8_t* payload = (uint8_t*)tcp_rcvd->payload;
        //   dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!READ IN DATA!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(getReceiveBAvailable(fd) < tcp_rcvd->length) {
            // dbg(TRANSPORT_CHANNEL, "Dropping packet. Can't fit data in buffer.\n");
            return FALSE;
        }
        if(sockets[fd-1].nextExpected != tcp_rcvd->seq) {
            // dbg(TRANSPORT_CHANNEL, "Incorrect sequence number %u. Expected %u Resending ACK.\n", tcp_rcvd->seq, sockets[fd-1].nextExpected);
            sendTCPPacket(fd, ACK);
            return FALSE;
        }
        // dbg(TRANSPORT_CHANNEL, "Reading in data with sequence number %u.\n", tcp_rcvd->seq);
        while(bytesRead < tcp_rcvd->length && getReceiveBAvailable(fd) > 0) {
            memcpy(&sockets[fd-1].rcvdBuff[(++sockets[fd-1].lastRcvd) % SOCKET_BUFFER_SIZE], payload+bytesRead, 1);
            bytesRead += 1;
        }
        // dbg(TRANSPORT_CHANNEL, "Last Received %u.\n", sockets[fd-1].lastRcvd);
        sockets[fd-1].nextExpected = sockets[fd-1].lastRcvd + 1;        
        // dbg(TRANSPORT_CHANNEL, "Next Expected %u.\n", sockets[fd-1].nextExpected);
        sockets[fd-1].advertisedWindow = SOCKET_BUFFER_SIZE - getRR(fd);
        // dbg(TRANSPORT_CHANNEL, "Advertised window %u.\n", sockets[fd-1].advertisedWindow);
        return TRUE;
    }

    void clearSocket(uint8_t fd) {
        uint8_t i;
        sockets[fd-1].flags = 0;
        sockets[fd-1].state = CLOSED;
        sockets[fd-1].src.port = 0;
        sockets[fd-1].src.addr = 0;
        sockets[fd-1].dest.port = 0;
        sockets[fd-1].dest.addr = 0;
        for(i = 0; i < MAX_NUM_OF_SOCKETS-1; i++) {
            sockets[fd-1].connectionQueue[i] = 0;
        }
        for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
            sockets[fd-1].sendBuff[i] = 0;
            sockets[fd-1].rcvdBuff[i] = 0;
        }
        i = (uint8_t)(call Random.rand16() % (SOCKET_BUFFER_SIZE<<1));
        sockets[fd-1].lastWritten = i;
        sockets[fd-1].lastAck = i;
        sockets[fd-1].lastSent = i;
        sockets[fd-1].lastRead = 0;
        sockets[fd-1].lastRcvd = 0;
        sockets[fd-1].nextExpected = 0;
        sockets[fd-1].RTT = TCP_INITIAL_RTT;
        sockets[fd-1].advertisedWindow = SOCKET_BUFFER_SIZE;
    }

    uint8_t copySocket(uint8_t fd, uint16_t addr, uint8_t port) {
        uint8_t i;
        //  dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!COPY SOCKET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].flags == 0) {
                sockets[i].src.port = sockets[fd-1].src.port;
                sockets[i].src.addr = sockets[fd-1].src.addr;
                sockets[i].dest.addr = addr;
                sockets[i].dest.port = port;
                return i+1;
            }
        }
        return 0;
    }

    /*
    * Interface methods
    */

    command void Transport.run() {
        uint8_t i;
        call TransmissionTimer.startOneShot(60*1024);
        //    dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!TRANSPORT START!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            clearSocket(i+1);
        }
    }

    event void TransmissionTimer.fired() {
        uint8_t i;
        //dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!TRANSMISSION FIRED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(call TransmissionTimer.isOneShot()) {
            dbg(TRANSPORT_CHANNEL, "TCP starting on node %u\n", TOS_NODE_ID);
            call TransmissionTimer.startPeriodic(1024 + (uint16_t) (call Random.rand16()%1000));
        }
        // Iterate over sockets
            // If timeout -> retransmit
            // If ESTABLISHED -> attempt to send packets
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].RTO < call TransmissionTimer.getNow()) {
                // dbg(TRANSPORT_CHANNEL, "Retransmitting!\n");     
                if(sockets[i].state == ESTABLISHED) {
                        if(sockets[i].lastSent != sockets[i].lastAck && sockets[i].type == CLIENT) {
                            // Go back N
                            sockets[i].lastSent = sockets[i].lastAck;
                            // Resend window
                            sendTheWindow(i+1);
                            // dbg(TRANSPORT_CHANNEL, "Resending at %u\n", sockets[i].lastSent+1);
                        }
						else{
						
						}
                }
                if(sockets[i].state == SYN_SENT){
						dbg(TRANSPORT_CHANNEL, "Resending SYN\n");
                        // Resend SYN
                        sendTCPPacket(i+1, SYN);
                }
                else if(sockets[i].state == SYN_RCVD){
                        // Resend SYN_ACK
                        sendTCPPacket(i+1, SYN_ACK);
						}
                else if(sockets[i].state == CLOSE_WAIT){
                        // Resend FIN
                        dbg(TRANSPORT_CHANNEL, "Sending last FIN. Going to LAST_ACK.\n");
                        sendTCPPacket(i+1, FIN);
                        sockets[i].state = LAST_ACK;
                        // Set final RTO
                        sockets[i].RTO = call TransmissionTimer.getNow() + (4 * sockets[i].RTT);
						}
                else if(sockets[i].state == FIN_WAIT_1){
                        // Resend FIN
                        dbg(TRANSPORT_CHANNEL, "Resending last FIN\n");
                        sendTCPPacket(i+1, FIN);
						}
                else if(sockets[i].state == TIME_WAIT || sockets[i].state == LAST_ACK){
                        // Timeout! Close the connection
                        sockets[i].state = CLOSED;
                        dbg(TRANSPORT_CHANNEL, "CONNECTION CLOSED!\n");
				}

            }
            if(sockets[i].state == ESTABLISHED && sockets[i].type == CLIENT) {
                // Send window
                sendTheWindow(i+1);
            } else if(sockets[i].state == LAST_ACK) {
                // Resend FIN
                dbg(TRANSPORT_CHANNEL, "Resending last FIN\n");
                sendTCPPacket(i+1, FIN);
            }
        }
    }    

    /**
    * Get a socket if there is one available.
    * @Side Client/Server
    * @return
    *    socket_t - return a socket file descriptor which is a number
    *    associated with a socket. If you are unable to allocated
    *    a socket then return a NULL socket_t.
    */
    command socket_t Transport.socket() {
        uint8_t i;
        // For socket in socket store
                       // dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!SOCKET!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            // If socket not in use
            if(sockets[i].state == CLOSED) {
                sockets[i].state = OPENED;
                // Return idx+1
                return (socket_t) i+1;
            }
        }
        // No socket found -> Return 0
        return 0;
    }

    /**
    * Bind a socket with an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       you are binding.
    * @param
    *    socket_addr_t *addr: the source port and source address that
    *       you are biding to the socket, fd.
    * @Side Client/Server
    * @return error_t - SUCCESS if you were able to bind this socket, FAIL
    *       if you were unable to bind.
    */
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        uint32_t socketId = 0;
        // Check for valid socket
                       // dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!BIND!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        // Check socket state and port
        if(sockets[fd-1].state == OPENED && !ports[addr->port]) {
            // Bind address and port to socket
            sockets[fd-1].src.addr = addr->addr;
            sockets[fd-1].src.port = addr->port;
            sockets[fd-1].state = NAMED;
            // Add the socket to the SocketMap
            socketId = (((uint32_t)addr->addr) << 24) | (((uint32_t)addr->port) << 16);
            call SocketMap.insert(socketId, fd);
            // Mark the port as used
            ports[addr->port] = TRUE;
            // Return SUCCESS
            return SUCCESS;
        }
        return FAIL;
    }

    /**
    * Checks to see if there are socket connections to connect to and
    * if there is one, connect to it.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting an accept. remember, only do on listen. 
    * @side Server
    * @return socket_t - returns a new socket if the connection is
    *    accepted. this socket is a copy of the server socket but with
    *    a destination associated with the destination address and port.
    *    if not return a null socket.
    */
    command socket_t Transport.accept(socket_t fd) {
        uint8_t i, conn;
        // Check for valid socket
                       // dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ACCEPT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return 0;
        }
        // For given socket
        for(i = 0; i < MAX_NUM_OF_SOCKETS-1; i++) {
            // If connectionQueue is not empty
            if(sockets[fd-1].connectionQueue[i] != 0) {
                conn = sockets[fd-1].connectionQueue[i];
                while(++i < MAX_NUM_OF_SOCKETS-1 && sockets[fd-1].connectionQueue[i] != 0) {
                    sockets[fd-1].connectionQueue[i-1] = sockets[fd-1].connectionQueue[i];
                }
                sockets[fd-1].connectionQueue[i-1] = 0;
                // Return the fd representing the connection
                return (socket_t) conn;
            }
        }
        return 0;
    }

    /**
    * Write to the socket from a buffer. This data will eventually be
    * transmitted through your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a write.
    * @param
    *    uint8_t *buff: the buffer data that you are going to wrte from.
    * @param
    *    uint16_t bufflen: The amount of data that you are trying to
    *       submit.
    * @Side For your project, only client side. This could be both though.
    * @return uint16_t - return the amount of data you are able to write
    *    from the pass buffer. This may be shorter then bufflen
    */
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t bytesWritten = 0;
        // Check for valid socket
                       // dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!WRITE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS || sockets[fd-1].state != ESTABLISHED) {
            return 0;
        }
        // Write all possible data to the given socket
        while(bytesWritten < bufflen && getSendBAvailable(fd) > 0) {
            memcpy(&sockets[fd-1].sendBuff[++sockets[fd-1].lastWritten % SOCKET_BUFFER_SIZE], buff+bytesWritten, 1);
            bytesWritten++;
        }
        // Return number of bytes written
        return bytesWritten;
    }

    /**
    * This will pass the packet so you can handle it internally.
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
    command error_t Transport.receive(pack* package) {
        uint8_t fd, newFd, src = package->src;
        tcp_pack* tcp_rcvd = (tcp_pack*) &package->payload;
        uint32_t socketId = 0;
               // dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!RECEIVE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(tcp_rcvd->flags == DATA){
             // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rcvd->destPort, src, tcp_rcvd->srcPort);

                if(sockets[fd-1].state == SYN_RCVD){
                      dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED!\n");
                        sockets[fd-1].state = ESTABLISHED;
                }else if (sockets[fd-1].state == ESTABLISHED){
                     //dbg(TRANSPORT_CHANNEL, "Data received on node %u via port %u\n", TOS_NODE_ID, tcp_rcvd->destPort);
                        if(readInData(fd, tcp_rcvd))
                            // Send ACK
                            sendTCPPacket(fd, ACK);
                        return SUCCESS;
                }
                return FAIL;
        }else if(tcp_rcvd->flags == ACK){
            // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rcvd->destPort, src, tcp_rcvd->srcPort);
                if(fd == 0)
                    return FAIL;
                sockets[fd-1].RTT = ((TCP_RTT_ALPHA) * (sockets[fd-1].RTT) + (100-TCP_RTT_ALPHA) * (call TransmissionTimer.getNow() - sockets[fd-1].RTX)) / 100; // calc RTT
                //dbg(TRANSPORT_CHANNEL, "RTT now %u\n", sockets[fd-1].RTT);

                if(sockets[fd-1].state == SYN_RCVD){
                    dbg(TRANSPORT_CHANNEL, "ACK received on node %u via port %u\n", TOS_NODE_ID, tcp_rcvd->destPort);
                        // Set state
                        sockets[fd-1].state = ESTABLISHED;
                        dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED!\n");
                        return SUCCESS;
                }else if(sockets[fd-1].state == ESTABLISHED){
                    // Data ACK
                        sockets[fd-1].lastAck = tcp_rcvd->ack - 1;
                        sockets[fd-1].advertisedWindow = tcp_rcvd->advertisedWindow;
                        return SUCCESS;
                }else if (sockets[fd-1].state == FIN_WAIT_1){
                    dbg(TRANSPORT_CHANNEL, "ACK received on node %u via port %u. Going to FIN_WAIT_2.\n", TOS_NODE_ID, tcp_rcvd->destPort);
                        // Set state
                        sockets[fd-1].state = FIN_WAIT_2;
                        return SUCCESS;
                }else if (sockets[fd-1].state == CLOSING){
                    // Set state
                        sockets[fd-1].state = TIME_WAIT;
                        return SUCCESS;
                }else if (sockets[fd-1].state == LAST_ACK){
                    dbg(TRANSPORT_CHANNEL, "Received last ack. ZEROing socket.\n");
                        clearSocket(fd);
                        // Set state
                        sockets[fd-1].state = CLOSED;
                        dbg(TRANSPORT_CHANNEL, "CONNECTION CLOSED!\n");
                        return SUCCESS;
                }
                return FAIL;
        }else if(tcp_rcvd->flags == SYN){
            // Find socket fd

                fd = getSocket(TOS_NODE_ID, tcp_rcvd->destPort, 0, 0);
                if(fd == 0){
                    return FAIL;
                }

                if(sockets[fd-1].state == LISTEN){
                    dbg(TRANSPORT_CHANNEL, "SYN recieved on node %u via port %u with seq %u\n", TOS_NODE_ID, tcp_rcvd->destPort, tcp_rcvd->seq);
                        // Create new active socket
                        newFd = copySocket(fd, package->src, tcp_rcvd->srcPort);
                        if(newFd > 0) {
                            // Add new connection to fd connection queue
                            addConn(fd, newFd);
                            // Set state
                            dbg(TRANSPORT_CHANNEL, "Received SYN with sequence num %u\n", tcp_rcvd->seq);
                            sockets[newFd-1].state = SYN_RCVD;
                            sockets[newFd-1].lastRead = tcp_rcvd->seq;
                            sockets[newFd-1].lastRcvd = tcp_rcvd->seq;
                            sockets[newFd-1].nextExpected = tcp_rcvd->seq + 1;
                            // Send SYN_ACK
                            sendTCPPacket(newFd, SYN_ACK);
                            dbg(TRANSPORT_CHANNEL, "SYN_ACK sent on node %u via port %u\n", TOS_NODE_ID, tcp_rcvd->destPort);
                            // Add the new fd to the socket map
                            socketId = (((uint32_t)TOS_NODE_ID) << 24) | (((uint32_t)tcp_rcvd->destPort) << 16) | (((uint32_t)src) << 8) | (((uint32_t)tcp_rcvd->srcPort));
                            call SocketMap.insert(socketId, newFd);
                            return SUCCESS;
                        }          
                }
                return FAIL;
        }else if(tcp_rcvd->flags == SYN_ACK){
            dbg(TRANSPORT_CHANNEL, "SYN_ACK received on node %u via port %u\n", TOS_NODE_ID, tcp_rcvd->destPort);
                // Look up the socket
                fd = getSocket(TOS_NODE_ID, tcp_rcvd->destPort, src, tcp_rcvd->srcPort);
                if(sockets[fd-1].state == SYN_SENT) {
                    // Set the advertised window
                    sockets[fd-1].advertisedWindow = tcp_rcvd->advertisedWindow;              
                    sockets[fd-1].state = ESTABLISHED;
                    // Send ACK
                    sendTCPPacket(fd, ACK);
                    dbg(TRANSPORT_CHANNEL, "ACK sent on node %u via port %u\n", TOS_NODE_ID, tcp_rcvd->destPort);
                    dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED!\n");
                    return SUCCESS;
                }
                return FAIL;
        }else if(tcp_rcvd->flags == FIN){
            // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rcvd->destPort, src, tcp_rcvd->srcPort);
                dbg(TRANSPORT_CHANNEL, "FIN Received\n");

                if(sockets[fd-1].state == ESTABLISHED){
                    dbg(TRANSPORT_CHANNEL, "Going to CLOSE_WAIT. Sending ACK.\n");
                        // Send ACK
                        sendTCPPacket(fd, ACK);                        
                        // Set state
                        sockets[fd-1].RTX = call TransmissionTimer.getNow();
                        sockets[fd-1].RTO = call TransmissionTimer.getNow() + (2 * sockets[fd-1].RTT);
                        sockets[fd-1].state = CLOSE_WAIT;
                        return SUCCESS;
                }else if(sockets[fd-1].state == FIN_WAIT_1){
                    // Send ACK
                        sendTCPPacket(fd, ACK);
                        // Set state
                        sockets[fd-1].state = CLOSING;
                        return SUCCESS;
                }else if(sockets[fd-1].state == TIME_WAIT){
                    // Send ACK
                        sendTCPPacket(fd, ACK);
                        // If not already in TIME_WAIT set state and new timeout
                        if(sockets[fd-1].state != TIME_WAIT) {
                            sockets[fd-1].state = TIME_WAIT;
                            sockets[fd-1].RTO = call TransmissionTimer.getNow() + (4 * sockets[fd-1].RTT);
                        }
                        return SUCCESS;
                }
                return FAIL;
        }else if(tcp_rcvd->flags == FIN_ACK){
            // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rcvd->destPort, src, tcp_rcvd->srcPort);
                if(sockets[fd-1].state == FIN_WAIT_1){
                        // Send ACK
                        sendTCPPacket(fd, ACK);
                        // Go to time_wait
                        return SUCCESS;  
                }
                return FAIL;
        }
        return FAIL;
    }
    /**
    * Read from the socket and write this data to the buffer. This data
    * is obtained from your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a read.
    * @param
    *    uint8_t *buff: the buffer that is being written.
    * @param
    *    uint16_t bufflen: the amount of data that can be written to the
    *       buffer.
    * @Side For your project, only server side. This could be both though.
    * @return uint16_t - return the amount of data you are able to read
    *    from the pass buffer. This may be shorter then bufflen
    */
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t bytesRead = 0;
        // Check for valid socket
                      //  dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!READ!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS || sockets[fd-1].state != ESTABLISHED) {
            return 0;
        }
        // Read all possible data from the given socket
        while(bytesRead < bufflen && getRR(fd) > 0) {
            memcpy(buff, &sockets[fd-1].rcvdBuff[(++sockets[fd-1].lastRead) % SOCKET_BUFFER_SIZE], 1);
            buff++;
            bytesRead++;
        }
        // Return number of bytes written
        return bytesRead;
    }

    /**
    * Attempts a connection to an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are attempting a connection with. 
    * @param
    *    socket_addr_t *addr: the destination address and port where
    *       you will atempt a connection.
    * @side Client
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a connection with the fd passed, else return FAIL.
    */
    command error_t Transport.connect(socket_t fd, socket_addr_t * dest) {
        uint32_t socketId = 0;
        // Check for valid socket
          //  dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!CONNECT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS || sockets[fd-1].state != NAMED) {
            return FAIL;
        }
        // Remove the old socket from the 
        socketId = (((uint32_t)sockets[fd-1].src.addr) << 24) | (((uint32_t)sockets[fd-1].src.port) << 16);
        call SocketMap.remove(socketId);
        // Add the dest to the socket
        sockets[fd-1].dest.addr = dest->addr;
        sockets[fd-1].dest.port = dest->port;
        sockets[fd-1].type = CLIENT;
        // Send SYN
        sendTCPPacket(fd, SYN);
        // Add new socket to SocketMap
        socketId |= (((uint32_t)dest->addr) << 8) | ((uint32_t)dest->port);
        call SocketMap.insert(socketId, fd);
        // Set SYN_SENT
        sockets[fd-1].state = SYN_SENT;

        dbg(TRANSPORT_CHANNEL, "SYN sent on node %u via port %u\n", TOS_NODE_ID, sockets[fd-1].src.port);
        return SUCCESS;
    }

    /**
    * Closes the socket.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are closing.
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
    command error_t Transport.close(socket_t fd) {
        uint32_t socketId = 0;
        // Check for valid socket
                    //    dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!CLOSE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        if(sockets[fd-1].state == LISTEN){
                // Remove from SocketMap
                socketId = (((uint32_t)sockets[fd-1].src.addr) << 24) | (((uint32_t)sockets[fd-1].src.port) << 16);
                call SocketMap.remove(socketId);
                // Free the port
                ports[sockets[fd-1].src.port] = FALSE;
                // Zero the socket
                clearSocket(fd);
                // Set CLOSED
                sockets[fd-1].state = CLOSED;
                return SUCCESS;
        }else if(sockets[fd-1].state == SYN_SENT){
                // Remove from SocketMap
                socketId = (((uint32_t)sockets[fd-1].src.addr) << 24) | (((uint32_t)sockets[fd-1].src.port) << 16) | (((uint32_t)sockets[fd-1].dest.addr) << 8) | ((uint32_t)sockets[fd-1].dest.port);
                call SocketMap.remove(socketId);
                // Zero the socket
                clearSocket(fd);
                // Set CLOSED
                sockets[fd-1].state = CLOSED;
                return SUCCESS;
        }else if(sockets[fd-1].state == SYN_RCVD){
                dbg(TRANSPORT_CHANNEL, "Sending FIN\n");
                // Initiate FIN sequence
                sendTCPPacket(fd, FIN);
                // Set FIN_WAIT_1
                dbg(TRANSPORT_CHANNEL, "Going to FIN_WAIT_1\n");
                sockets[fd-1].state = FIN_WAIT_1;
                return SUCCESS;
        }else if(sockets[fd-1].state == CLOSE_WAIT){
                // Continue FIN sequence
                sendTCPPacket(fd, FIN);
                // Set LAST_ACK
                sockets[fd-1].state = LAST_ACK;
                return SUCCESS;
        }else{
            return FAIL;
        }
        return FAIL;
    }

    /**
    * A hard close, which is not graceful. This portion is optional.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing.
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
    command error_t Transport.release(socket_t fd) {
        uint8_t i;
        // Check for valid socket
                     //   dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!RELEASE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        // Clear socket info
        clearSocket(fd);
        return SUCCESS;
    }

    /**
    * Listen to the socket and wait for a connection.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Server
    * @return error_t - returns SUCCESS if you are able change the state 
    *   to listen else FAIL.
    */
    command error_t Transport.listen(socket_t fd) {        
        // Check for valid socket
                    //    dbg(TRANSPORT_CHANNEL, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!LISTEN!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");

        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        // If socket is bound
        if(sockets[fd-1].state == NAMED) {
            // Set socket to LISTEN
            sockets[fd-1].state = LISTEN;
            // Add socket to SocketMap
            return SUCCESS;
        } else {
            return FAIL;
        }
    }

    command void Transport.startServer(uint8_t port) {
        uint8_t i;
        uint32_t connId;
        socket_addr_t addr;
        if(numServers >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Cannot start server\n");
            return;
        }
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            // Skip occupied server structs
            if(server[i].sockfd != 0)
                continue;
            // Open a socket
            server[i].sockfd = call Transport.socket();
            if(server[i].sockfd > 0) {
                // Set up some structs
                addr.addr = TOS_NODE_ID;
                addr.port = port;
                // Bind the socket to the src address
                if(call Transport.bind(server[i].sockfd, &addr) == SUCCESS) {
                    // Add the bound socket index to the connection map
                    connId = ((uint32_t)addr.addr << 24) | ((uint32_t)addr.port << 16);
                    call ConnectionMap.insert(connId, i+1);
                    // Set up some state for the connection
                    server[i].bytesRead = 0;
                    server[i].bytesWritten = 0;
                    server[i].numConns = 0;
                    // Listen on the port and start a timer if needed
                    if(call Transport.listen(server[i].sockfd) == SUCCESS && !(call AppTimer.isRunning())) {
                        call AppTimer.startPeriodic(1024 + (uint16_t) (call Random.rand16()%1000));
                    }
                    numServers++;
                    return;
                }
            }
        }
    }

    command void Transport.startClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer) {
        uint8_t i;
        uint32_t connId;
        socket_addr_t clientAddr;
        socket_addr_t serverAddr;
        // Check if there is available space
        if(numClients >= MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Cannot start client\n");
            return;
        }
        // Set up some structs
        clientAddr.addr = TOS_NODE_ID;
        clientAddr.port = srcPort;
        serverAddr.addr = dest;
        serverAddr.port = destPort;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            // Skip occupied client structs
            if(client[i].sockfd != 0) {
                continue;
            }
            // Open a socket
            client[i].sockfd = call Transport.socket();
            if(client[i].sockfd == 0) {
                dbg(TRANSPORT_CHANNEL, "No available sockets. Exiting!");
                return;
            }
            // Bind the socket to the src address
            if(call Transport.bind(client[i].sockfd, &clientAddr) == FAIL) {
                dbg(TRANSPORT_CHANNEL, "Failed to bind sockets. Exiting!");
                return;
            }
            // Add the bound socket index to the connection map
            connId = ((uint32_t)TOS_NODE_ID << 24) | ((uint32_t)srcPort << 16);
            call ConnectionMap.insert(connId, i+1);
            // Connect to the remote server
            if(call Transport.connect(client[i].sockfd, &serverAddr) == FAIL) {
                dbg(TRANSPORT_CHANNEL, "Failed to connect to server. Exiting!");
                return;
            }
            // Remove the old connection and add the newly connected socket index
            call ConnectionMap.remove(connId);
            connId = ((uint32_t)TOS_NODE_ID << 24) | ((uint32_t)srcPort << 16) | ((uint32_t)dest << 16) | ((uint32_t)destPort << 16);
            call ConnectionMap.insert(connId, i+1);
            // Set up some state for the connection
            client[i].transfer = transfer;
            client[i].counter = 0;
            client[i].bytesWritten = 0;
            client[i].bytesTransferred = 0;
            // Start the timer if it isn't running
            if(!(call AppTimer.isRunning())) {
                call AppTimer.startPeriodic(1024 + (uint16_t) (call Random.rand16()%1000));
            }
            numClients++;
            return;
        }
    }

    command void Transport.closeClient(uint8_t srcPort, uint8_t destPort, uint8_t dest) {
        uint32_t sockIdx, connId;
        // Find the correct socket index
        connId = ((uint32_t)TOS_NODE_ID << 24) | ((uint32_t)srcPort << 16) | ((uint32_t)dest << 16) | ((uint32_t)destPort << 16);
        sockIdx = call ConnectionMap.get(connId);
        if(sockIdx == 0) {
            dbg(TRANSPORT_CHANNEL, "Client not found\n");
            return;
        }
        // Close the socket
        call Transport.close(client[sockIdx-1].sockfd);
        // Zero the client & decrement connections
        client[sockIdx-1].sockfd = 0;
        client[sockIdx-1].bytesWritten = 0;
        client[sockIdx-1].bytesTransferred = 0;
        client[sockIdx-1].counter = 0;
        client[sockIdx-1].transfer = 0;
        numClients--;
    }

    

    void startServer() {
        uint8_t i, j, bytes, newFd;
        uint16_t data, length;
        bool isRead = FALSE;
        bytes = 0;
        for(i = 0; i < numServers; i++) {
            if(server[i].sockfd == 0) {
                continue;
            }
            // Accept any new connections
            newFd = call Transport.accept(server[i].sockfd);
            if(newFd > 0) {
                if(server[i].numConns < MAX_NUM_OF_SOCKETS-1) {
                    server[i].conns[server[i].numConns++] = newFd;
                }
            }
            // Iterate over connections and read
            for(j = 0; j < server[i].numConns; j++) {
                if(server[i].conns[j] != 0) {
                    if((TCP_APP_BUFFER_SIZE - getServerBOccupied(i) - 1) > 0) {
                        length = min((TCP_APP_BUFFER_SIZE - server[i].bytesWritten), TCP_APP_READ_SIZE);
                        bytes += call Transport.read(server[i].conns[j], &server[i].buffer[server[i].bytesWritten], length);
                        server[i].bytesWritten += bytes;
                        if(server[i].bytesWritten == TCP_APP_BUFFER_SIZE) {
                            server[i].bytesWritten = 0;
                        }
                    }
                }
            }
            // Print out received data
            while(getServerBOccupied(i) >= 2) {
                if(!isRead) {
                    dbg(TRANSPORT_CHANNEL, "Reading Data at %u: ", server[i].bytesRead);
                    isRead = TRUE;
                }
                if(server[i].bytesRead == TCP_APP_BUFFER_SIZE) {
                    server[i].bytesRead = 0;
                }
                data = (((uint16_t)server[i].buffer[server[i].bytesRead+1]) << 8) | (uint16_t)server[i].buffer[server[i].bytesRead];
                printf("%u,", data);
                server[i].bytesRead += 2;
            }
            if(isRead)
                printf("\n");
        }
    }

    void startClient() {
        uint8_t i;
        uint16_t bytesTransferred, bytesToTransfer;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(client[i].sockfd == 0)
                continue;
            // Writing to buffer
            while((TCP_APP_BUFFER_SIZE - getClientBOccupied(i) - 1) > 0 && client[i].counter < client[i].transfer) {
                if(client[i].bytesWritten == TCP_APP_BUFFER_SIZE) {
                    client[i].bytesWritten = 0;
                }
                if((client[i].bytesWritten & 1) == 0) {
                    client[i].buffer[client[i].bytesWritten] = client[i].counter & 0xFF;
                } else {
                    client[i].buffer[client[i].bytesWritten] = client[i].counter >> 8;
                    client[i].counter++;
                }
                client[i].bytesWritten++;
            }
            // Writing to socket
            if(getClientBOccupied(i) > 0) {
                bytesToTransfer = min((TCP_APP_BUFFER_SIZE - client[i].bytesTransferred), (client[i].bytesWritten - client[i].bytesTransferred));
                bytesTransferred = call Transport.write(client[i].sockfd, &client[i].buffer[client[i].bytesTransferred], bytesToTransfer);
                client[i].bytesTransferred += bytesTransferred;
            }
            if(client[i].bytesTransferred == TCP_APP_BUFFER_SIZE)
                client[i].bytesTransferred = 0;
        }
    }

    uint16_t getServerBOccupied(uint8_t idx) {
        if(server[idx].bytesRead == server[idx].bytesWritten) {
            return 0;
        } else if(server[idx].bytesRead < server[idx].bytesWritten) {
            return server[idx].bytesWritten - server[idx].bytesRead;
        } else {
            return (TCP_APP_BUFFER_SIZE - server[idx].bytesRead) + server[idx].bytesWritten;
        }
    }


    uint16_t getClientBOccupied(uint8_t idx) {
        if(client[idx].bytesTransferred == client[idx].bytesWritten) {
            return 0;
        } else if(client[idx].bytesTransferred < client[idx].bytesWritten) {
            return client[idx].bytesWritten - client[idx].bytesTransferred;
        } else {
            return (TCP_APP_BUFFER_SIZE - client[idx].bytesTransferred) + client[idx].bytesWritten;
        }
    }

    event void AppTimer.fired() {
        startServer();
        startClient();

    }
}