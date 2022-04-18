#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/tcp.h"

module TransportP{
    provides interface Transport;
    uses interface SimpleSend as Sender;
    //uses interface Receive as Receiver;
    uses interface Timer<TMilli> as PeriodicTimer;
    uses interface NeighborDiscovery;
    uses interface RoutingTable;
    uses interface Hashmap<uint8_t> as HashMap;
}
/**
 * The Transport interface handles sockets and is a layer of abstraction
 * above TCP. This will be used by the application layer to set up TCP
 * packets. Internally the system will be handling syn/ack/data/fin
 * Transport packets.
 *
 * @project
 *   Transmission Control Protocol
 * @author
 *      Alex Beltran - abeltran2@ucmerced.edu
 * @date
 *   2013/11/12
 */
implementation{
    pack ippack;
    struct tcp tcppack;
    bool ports[NUM_SUPPORTED_PORTS];
    error_t clearsocket(socket_t fd);
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    error_t clearsocket(socket_t fd); 
    //void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t payload, uint8_t length); 
    uint16_t getReceiverReadable(uint8_t fd); 
    uint16_t getSenderDataInFlight(uint8_t fd); 
    uint16_t getSendBufferOccupied(uint8_t fd); 
    uint16_t getSBAvailable(uint8_t fd); 
    uint16_t min(uint16_t a, uint16_t b); 
    uint8_t calcEffWindow(uint8_t fd);
    uint8_t getSocket(uint8_t src, uint8_t srcPort, uint8_t dest, uint8_t destPort); 
    uint16_t getRBAvailable(uint8_t fd);
    void calculateRTO(uint8_t fd); 
    uint8_t calcAdvWindow(uint8_t fd);
    uint8_t cloneSocket(uint8_t fd, uint16_t addr, uint8_t port);
    uint8_t sendTCPPacket(uint8_t fd, uint8_t flags);
    bool readData(uint8_t fd, struct tcp* tcp_rcvd); 


	command void Transport.start() {
        uint8_t i;
        call PeriodicTimer.startOneShot(60*1024);
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            clearsocket(i+1);
        }
    }

    command uint8_t Transport.send(pack* msg, uint8_t dest){
        struct tcp* tcp_rc = (struct tcp*) msg->payload;
        uint8_t fd;
        fd = getSocket(TOS_NODE_ID, tcp_rc->destport, dest, tcp_rc->srcport);
        sendTCPPacket(fd, DATA);
    }

    void sendWindow(uint8_t fd) {
        uint16_t bytesRemaining = min(getSendBufferOccupied(fd), calcEffWindow(fd));
        uint8_t bytesSent;
        while(bytesRemaining > 0 && bytesSent > 0) {
            bytesSent = sendTCPPacket(fd, DATA);
            bytesRemaining -= bytesSent;
        }
    }

	event void PeriodicTimer.fired() {
        uint8_t i;
        if(call PeriodicTimer.isOneShot()) {
            dbg(TRANSPORT_CHANNEL, "TCP starting on node %u\n", TOS_NODE_ID);
            call PeriodicTimer.startPeriodic(1024);
        }
        // Iterate over sockets
            // If timeout -> retransmit
            // If ESTABLISHED -> attempt to send packets
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].RTO < call PeriodicTimer.getNow()) {
                // dbg(TRANSPORT_CHANNEL, "Retransmitting!\n");
                switch(sockets[i].state) {
                    case ESTABLISHED:
                        if(sockets[i].lastSent != sockets[i].lastAck && sockets[i].type == CLIENT) {
                            // Go back N
                            sockets[i].lastSent = sockets[i].lastAck;
                            // Resend window
                            sendWindow(i+1);
                            // dbg(TRANSPORT_CHANNEL, "Resending at %u\n", sockets[i].lastSent+1);
                            continue;
                        }
                        break;
                    case SYN_SENT:
                        dbg(TRANSPORT_CHANNEL, "Resending SYN\n");
                        // Resend SYN
                        sendTCPPacket(i+1, SYN);
                        break;
                    case SYN_RCVD:
                        // Resend SYN_ACK
                        sendTCPPacket(i+1, SYN_ACK);
                        break;
                    case CLOSE_WAIT:
                        // Resend FIN
                        dbg(TRANSPORT_CHANNEL, "Sending last FIN. Going to LAST_ACK.\n");
                        sendTCPPacket(i+1, FIN);
                        sockets[i].state = LAST_ACK;
                        // Set final RTO
                        sockets[i].RTO = call PeriodicTimer.getNow() + (4 * sockets[i].RTT);
                        break;
                    case FIN_WAIT_1:
                        // Resend FIN
                        dbg(TRANSPORT_CHANNEL, "Resending last FIN\n");
                        sendTCPPacket(i+1, FIN);
                        break;
                    case LAST_ACK:
                    case TIME_WAIT:
                        // Timeout! Close the connection
                        sockets[i].state = CLOSED;
                        dbg(TRANSPORT_CHANNEL, "CONNECTION CLOSED!\n");
                }
            }
            if(sockets[i].state == ESTABLISHED && sockets[i].type == CLIENT) {
                // Send window
                sendWindow(i+1);
            } else if(sockets[i].state == LAST_ACK) {
                // Resend FIN
                dbg(TRANSPORT_CHANNEL, "Resending last FIN\n");
                sendTCPPacket(i+1, FIN);
            }
        }
    }

void addConnection(uint8_t fd, uint8_t conn) {
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS-1; i++) {
            if(sockets[fd-1].connections[i] == 0) {
                sockets[fd-1].connections[i] = conn;
                break;
            }
        }
    }

	error_t clearsocket(socket_t fd){
        uint8_t i;
        sockets[fd - 1].flag = 0;
        sockets[fd - 1].state = CLOSED;
        sockets[fd-1].src.port = 0;
        sockets[fd-1].src.addr = 0;
        sockets[fd-1].dest.port = 0;
        sockets[fd-1].dest.addr = 0;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            sockets[fd - 1].connections[i] = 0;
        }
        for(i = 0; i < SOCKET_BUFFER_SIZE; i++){
            sockets[fd - 1].sendBuff[i] = 0;
            sockets[fd - 1].rcvdBuff[i] = 0;
        }
        i = OutOfRange;
        sockets[fd - 1].lastAck = i;
        sockets[fd - 1].lastWritten = i;
        sockets[fd - 1].lastSent = i;
        sockets[fd - 1].lastRead = 0;
        sockets[fd - 1].lastRcvd = 0;
        sockets[fd - 1].nextExpected = 0;
        sockets[fd - 1].RTT = DEFAULT_RTT;
        sockets[fd - 1].effectiveWindow = SOCKET_BUFFER_SIZE;
        return SUCCESS;
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t seq, uint16_t protocol, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

	uint16_t getReceiverReadable(uint8_t fd) {
        uint16_t lastRead, nextExpected;
        lastRead = sockets[fd-1].lastRead % SOCKET_BUFFER_SIZE;
        nextExpected = sockets[fd-1].nextExpected % SOCKET_BUFFER_SIZE;
        if(lastRead < nextExpected)
            return nextExpected - lastRead - 1;        
        else
            return SOCKET_BUFFER_SIZE - lastRead + nextExpected - 1;        
    }


    uint16_t getSenderDataInFlight(uint8_t fd) {
        uint16_t lastAck, lastSent;
        lastAck = sockets[fd-1].lastAck % SOCKET_BUFFER_SIZE;
        lastSent = sockets[fd-1].lastSent % SOCKET_BUFFER_SIZE;
        if(lastAck <= lastSent)
            return lastSent - lastAck;
        else
            return SOCKET_BUFFER_SIZE - lastAck + lastSent;
    }

	uint16_t getSendBufferOccupied(uint8_t fd) {
        uint8_t lastSent, lastWritten;
        lastSent = sockets[fd-1].lastSent % SOCKET_BUFFER_SIZE;
        lastWritten = sockets[fd-1].lastWritten % SOCKET_BUFFER_SIZE;
        if(lastSent <= lastWritten)
            return lastWritten - lastSent;
        else
            return lastWritten + (SOCKET_BUFFER_SIZE - lastSent);
    }

    uint16_t getSBAvailable(uint8_t fd) {
        uint8_t ack, wr;
        ack = sockets[fd-1].lastAck % SOCKET_BUFFER_SIZE;
        wr = sockets[fd-1].lastWritten % SOCKET_BUFFER_SIZE;
        if(ack == wr)
            return SOCKET_BUFFER_SIZE - 1;
        else if(ack > wr)
            return ack - wr - 1;
        else
            return ack + (SOCKET_BUFFER_SIZE - wr) - 1;
    }

    uint16_t min(uint16_t a, uint16_t b) {
        if(a <= b)
            return a;
        else
            return b;
    }

    uint8_t calcEffWindow(uint8_t fd) {
        return sockets[fd-1].effectiveWindow - getSenderDataInFlight(fd);
    }

    uint8_t getSocket(uint8_t src, uint8_t srcPort, uint8_t dest, uint8_t destPort) {
        uint32_t Id = (((uint32_t)src) << 24) | (((uint32_t)srcPort) << 16) | (((uint32_t)dest) << 8) | (((uint32_t)destPort));
        return call HashMap.get(Id);
    }

    uint16_t getRBAvailable(uint8_t fd) {
        uint8_t lastRead, lastRcvd;
        lastRead = sockets[fd-1].lastRead % SOCKET_BUFFER_SIZE;
        lastRcvd = sockets[fd-1].lastRcvd % SOCKET_BUFFER_SIZE;
        if(lastRead == lastRcvd)
            return SOCKET_BUFFER_SIZE - 1;
        else if(lastRead > lastRcvd)
            return lastRead - lastRcvd - 1;
        else
            return lastRead + (SOCKET_BUFFER_SIZE - lastRcvd) - 1;
    }

	void calculateRTO(uint8_t fd) {
        sockets[fd-1].RTO = call PeriodicTimer.getNow() + (2 * sockets[fd-1].RTT);
    }

    void calculateRTT(uint8_t fd) {
        sockets[fd-1].RTT = ((TCP_RTT_ALPHA) * (sockets[fd-1].RTT) + (100-TCP_RTT_ALPHA) * (call PeriodicTimer.getNow() - sockets[fd-1].RTX)) / 100;
    }

	uint8_t calcAdvWindow(uint8_t fd) {
        return SOCKET_BUFFER_SIZE - getReceiverReadable(fd);
    }

	uint8_t cloneSocket(uint8_t fd, uint16_t addr, uint8_t port) {
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].flag == 0) {
                sockets[i].src.port = sockets[fd-1].src.port;
                sockets[i].src.addr = sockets[fd-1].src.addr;
                sockets[i].dest.addr = addr;
                sockets[i].dest.port = port;
                return i+1;
            }
        }
        return 0;
    }

    uint8_t sendTCPPacket(uint8_t fd, uint8_t flags) {
        uint8_t length, bytes = 0;
        uint8_t* payload = (uint8_t*)tcppack.payload;
        // Set up packet info
        tcppack.srcport = sockets[fd-1].src.port;
        tcppack.destport = sockets[fd-1].dest.port;
        tcppack.flag = flags;
        tcppack.adwin = sockets[fd-1].effectiveWindow;
        tcppack.ackNUM = sockets[fd-1].nextExpected;
        // Send initial sequence number or next expected
        if(flags == SYN) {
            tcppack.seqNUM = sockets[fd-1].lastSent;
        } else {
            tcppack.seqNUM = sockets[fd-1].lastSent + 1;
        }
        if(flags == DATA) {
            // Choose the min of the effective window, the number of bytes available to send, and the max packet size
            length = min(calcEffWindow(fd), min(getSendBufferOccupied(fd), TCP_PAYLOAD_SIZE));
            length ^= length & 1;
            if(length == 0) {
                return 0;
            }
            while(bytes < length) {
                memcpy(payload+bytes, &sockets[fd-1].sendBuff[(++sockets[fd-1].lastSent) % SOCKET_BUFFER_SIZE], 1);
                bytes += 1;
            }
            tcppack.hdrLen = length;
        }
        if(flags != ACK) {
            sockets[fd-1].RTX = call PeriodicTimer.getNow();
            calculateRTO(fd);
        }
        makePack(&ippack, TOS_NODE_ID, sockets[fd-1].dest.addr, MAX_TTL, 0, PROTOCOL_TCP, (uint8_t*)&tcppack, sizeof(struct tcp));
        call RoutingTable.DVRouting(&ippack);
        return bytes;
    }




    bool readData(uint8_t fd, struct tcp* tcp_rcvd) {
        uint16_t read = 0;
        uint8_t* payload = (uint8_t*)tcp_rcvd->payload;
        if(getRBAvailable(fd) < tcp_rcvd->hdrLen) {
            // dbg(TRANSPORT_CHANNEL, "Dropping packet. Can't fit data in buffer.\n");
            return FALSE;
        }
        if(sockets[fd-1].nextExpected != tcp_rcvd->seqNUM) {
            // dbg(TRANSPORT_CHANNEL, "Incorrect sequence number %u. Expected %u Resending ACK.\n", tcp_rcvd->seq, sockets[fd-1].nextExpected);
            sendTCPPacket(fd, ACK);
            return FALSE;
        }
        // dbg(TRANSPORT_CHANNEL, "Reading in data with sequence number %u.\n", tcp_rcvd->seq);
        while(read < tcp_rcvd->hdrLen && getRBAvailable(fd) > 0) {
            memcpy(&sockets[fd-1].rcvdBuff[(++sockets[fd-1].lastRcvd) % SOCKET_BUFFER_SIZE], payload+read, 1);
            read += 1;
        }
        // dbg(TRANSPORT_CHANNEL, "Last Received %u.\n", sockets[fd-1].lastRcvd);
        sockets[fd-1].nextExpected = sockets[fd-1].lastRcvd + 1;        
        // dbg(TRANSPORT_CHANNEL, "Next Expected %u.\n", sockets[fd-1].nextExpected);
        sockets[fd-1].effectiveWindow = calcAdvWindow(fd);
        // dbg(TRANSPORT_CHANNEL, "Advertised window %u.\n", sockets[fd-1].effectiveWindow);
        return TRUE;
    }


    /**
    * Get a socket if there is one available.
    * @Side Client/Server
    * @return
    *    socket_t - return a socket file descriptor which is a number
    *    associated with a socket. If you are unable to allocated
    *    a socket then return a NULL socket_t.
    */
    command socket_t Transport.socket(){
		uint8_t temp;
        for(temp = 0; temp < 10; temp++){
            if(sockets[temp].state == CLOSED){
                sockets[temp].state = ESTABLISHED;
                return (socket_t) temp + 1;
            }
        }
        return (socket_t) 0;
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
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr){
        uint32_t Id = 0;
        // check to see if fd is greater than the Max number of sockets or even defined. 
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return FAIL; // if FD is out of scope then FAIL
        }
        // if socket and port are ready then continue else fail 
        if(sockets[fd-1].state == ESTABLISHED && !ports[addr->port]) {
            // Bind address and port to socket
            sockets[fd-1].src.addr = addr->addr;
            sockets[fd-1].src.port = addr->port;

            // Add socket to map
            Id = (((uint32_t)addr->addr) << 24) | (((uint32_t)addr->port) << 16);
            call HashMap.insert(Id, fd);

            // Set port to being used 
            ports[addr->port] = TRUE;
            // Return SUCCESS so FAIL does not trigger
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
    command socket_t Transport.accept(socket_t fd){
        uint8_t j, cxn;
        // Check for valid socket
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS) {
            return 0;
        }
        // For given socket
        for(j = 0; j < MAX_NUM_OF_SOCKETS-1; j++) {
            // If connections is not empty
            if(sockets[fd-1].connections[j] != 0) {
                cxn = sockets[fd-1].connections[j];
                while(++j < MAX_NUM_OF_SOCKETS-1 && sockets[fd-1].connections[j] != 0) {
                    sockets[fd-1].connections[j-1] = sockets[fd-1].connections[j];
                }
                sockets[fd-1].connections[j-1] = 0;
                // Return the fd representing the connection
                return (socket_t) cxn;
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
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t len){
         uint16_t wr = 0;
        // Check for valid socket
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS || sockets[fd-1].state != ESTABLISHED) {
            return 0;
        }
        // Write all possible data to the given socket
        while(wr < len && getSBAvailable(fd) > 0) {
            memcpy(&sockets[fd-1].sendBuff[++sockets[fd-1].lastWritten % SOCKET_BUFFER_SIZE], buff+wr, 1);
            wr++;
        }
        // Return number of bytes written
        return wr;
    }
    /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
    command error_t Transport.receive(pack* package){
        uint8_t fd, newFd, src = package->src;
        struct tcp* tcp_rc = (struct tcp*) &package->payload;
        uint32_t Id = 0;
        switch(tcp_rc->flag) {
            case DATA:
                // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rc->destport, src, tcp_rc->srcport);
                switch(sockets[fd-1].state) {
                    case SYN_RCVD:
                        dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED!\n");
                        sockets[fd-1].state = ESTABLISHED;
                    case ESTABLISHED:
                        dbg(TRANSPORT_CHANNEL, "Data received on node %u via port %u\n", TOS_NODE_ID, tcp_rc->destport);
                        if(readData(fd, tcp_rc))
                            // Send ACK
                            sendTCPPacket(fd, ACK);
                        return SUCCESS;
                }
                break;
            case ACK:
                // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rc->destport, src, tcp_rc->srcport);
                if(fd == 0)
                    break;
                calculateRTT(fd);
                //dbg(TRANSPORT_CHANNEL, "RTT now %u\n", sockets[fd-1].RTT);
                switch(sockets[fd-1].state) {
                    case SYN_RCVD:
                        dbg(TRANSPORT_CHANNEL, "ACK received on node %u via port %u\n", TOS_NODE_ID, tcp_rc->destport);
                        // Set state
                        sockets[fd-1].state = ESTABLISHED;
                        dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED!\n");
                        return SUCCESS;
                    case ESTABLISHED:
                        // Data ACK
                        sockets[fd-1].lastAck = tcp_rc->ackNUM - 1;
                        sockets[fd-1].effectiveWindow = tcp_rc->adwin;
                        return SUCCESS;
                    case FIN_WAIT_1:
                        dbg(TRANSPORT_CHANNEL, "ACK received on node %u via port %u. Going to FIN_WAIT_2.\n", TOS_NODE_ID, tcp_rc->destport);
                        // Set state
                        sockets[fd-1].state = FIN_WAIT_2;
                        return SUCCESS;
                    case CLOSING:
                        // Set state
                        sockets[fd-1].state = TIME_WAIT;
                        return SUCCESS;
                    case LAST_ACK:
                        dbg(TRANSPORT_CHANNEL, "Received last ack. ZEROing socket.\n");
                        clearsocket(fd);
                        // Set state
                        sockets[fd-1].state = CLOSED;
                        dbg(TRANSPORT_CHANNEL, "CONNECTION CLOSED!\n");
                        return SUCCESS;
                }
                break;
            case SYN:
                // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rc->destport, 0, 0);
                if(fd == 0)
                    break;
                switch(sockets[fd-1].state) {
                    case LISTEN:
                        dbg(TRANSPORT_CHANNEL, "SYN recieved on node %u via port %u with seq %u\n", TOS_NODE_ID, tcp_rc->destport, tcp_rc->seqNUM);
                        // Create new active socket
                        newFd = cloneSocket(fd, package->src, tcp_rc->srcport);
                        if(newFd > 0) {
                            // Add new connection to fd connection queue
                            addConnection(fd, newFd);
                            // Set state
                            dbg(TRANSPORT_CHANNEL, "Received SYN with sequence num %u\n", tcp_rc->seqNUM);
                            sockets[newFd-1].state = SYN_RCVD;
                            sockets[newFd-1].lastRead = tcp_rc->seqNUM;
                            sockets[newFd-1].lastRcvd = tcp_rc->seqNUM;
                            sockets[newFd-1].nextExpected = tcp_rc->seqNUM + 1;
                            // Send SYN_ACK
                            sendTCPPacket(newFd, SYN_ACK);
                            dbg(TRANSPORT_CHANNEL, "SYN_ACK sent on node %u via port %u\n", TOS_NODE_ID, tcp_rc->destport);
                            // Add the new fd to the socket map
                            Id = (((uint32_t)TOS_NODE_ID) << 24) | (((uint32_t)tcp_rc->destport) << 16) | (((uint32_t)src) << 8) | (((uint32_t)tcp_rc->srcport));
                            call HashMap.insert(Id, newFd);
                            return SUCCESS;
                        }                        
                }
                break;
            case SYN_ACK:
                dbg(TRANSPORT_CHANNEL, "SYN_ACK received on node %u via port %u\n", TOS_NODE_ID, tcp_rc->destport);
                // Look up the socket
                fd = getSocket(TOS_NODE_ID, tcp_rc->destport, src, tcp_rc->srcport);
                if(sockets[fd-1].state == SYN_SENT) {
                    // Set the advertised window
                    sockets[fd-1].effectiveWindow = tcp_rc->adwin;              
                    sockets[fd-1].state = ESTABLISHED;
                    // Send ACK
                    sendTCPPacket(fd, ACK);
                    dbg(TRANSPORT_CHANNEL, "ACK sent on node %u via port %u\n", TOS_NODE_ID, tcp_rc->destport);
                    dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED!\n");
                    return SUCCESS;
                }
                break;
            case FIN:
                // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rc->destport, src, tcp_rc->srcport);
                dbg(TRANSPORT_CHANNEL, "FIN Received\n");
                switch(sockets[fd-1].state) {
                    case ESTABLISHED:
                        dbg(TRANSPORT_CHANNEL, "Going to CLOSE_WAIT. Sending ACK.\n");
                        // Send ACK
                        sendTCPPacket(fd, ACK);                        
                        // Set state
                        sockets[fd-1].RTX = call PeriodicTimer.getNow();
                        calculateRTO(fd);
                        sockets[fd-1].state = CLOSE_WAIT;
                        return SUCCESS;
                    case FIN_WAIT_1:
                        // Send ACK
                        sendTCPPacket(fd, ACK);
                        // Set state
                        sockets[fd-1].state = CLOSING;
                        return SUCCESS;
                    case FIN_WAIT_2:
                    case TIME_WAIT:
                        // Send ACK
                        sendTCPPacket(fd, ACK);
                        // If not already in TIME_WAIT set state and new timeout
                        if(sockets[fd-1].state != TIME_WAIT) {
                            sockets[fd-1].state = TIME_WAIT;
                            sockets[fd-1].RTO = call PeriodicTimer.getNow() + (4 * sockets[fd-1].RTT);
                        }
                        return SUCCESS;
                }
                break;
            case FIN_ACK:
                // Find socket fd
                fd = getSocket(TOS_NODE_ID, tcp_rc->destport, src, tcp_rc->srcport);
                switch(sockets[fd-1].state) {
                    case FIN_WAIT_1:
                        // Send ACK
                        sendTCPPacket(fd, ACK);
                        // Go to time_wait
                        return SUCCESS;             
                }
                break;
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
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
		uint16_t Read = 0;
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS || sockets[fd - 1].state != ESTABLISHED) {
            return 0;
        }
        while(Read < bufflen && getReceiverReadable(fd) > 0) {
            memcpy(buff, &sockets[fd-1].rcvdBuff[(++sockets[fd - 1].lastRead) % SOCKET_BUFFER_SIZE], 1);
            buff++;
            Read++;
        }
        return Read;
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
    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
		uint32_t socketid = 0;
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS || sockets[fd-1].state != ESTABLISHED) {
            return FAIL;
        }
        socketid = (((uint32_t)sockets[fd-1].src.addr) << 24) | (((uint32_t)sockets[fd-1].src.port) << 16);
        call HashMap.remove(socketid);
        // Add the dest to the socket
        sockets[fd-1].dest.addr = addr->addr;
        sockets[fd-1].dest.port = addr->port;
        sockets[fd-1].type = CLIENT;
        // Send SYN
        sendTCPPacket(fd, SYN);
        // Add new socket to HashMap
        socketid |= (((uint32_t)addr -> addr) << 8) | ((uint32_t)addr -> port);
        call HashMap.insert(socketid, fd);
        // Set SYN_SENT
        sockets[fd - 1].state = SYN_SENT;
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
    command error_t Transport.close(socket_t fd){
		uint32_t socketid = 0;
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS){
            return FAIL;
        }
        if(sockets[fd - 1].state == LISTEN){
            socketid = (((uint32_t)sockets[fd - 1].src.addr) << 24) | (((uint32_t)sockets[fd - 1].src.port) << 16);
            call HashMap.remove(socketid);
            ports[sockets[fd - 1].src.addr] = FALSE;
            clearsocket(fd);
            sockets[fd - 1].state = CLOSED;
            return SUCCESS;
        }
        if(sockets[fd - 1].state == SYN_SENT){
            socketid = (((uint32_t)sockets[fd-1].src.addr) << 24) | (((uint32_t)sockets[fd-1].src.port) << 16) | (((uint32_t)sockets[fd-1].dest.addr) << 8) | ((uint32_t)sockets[fd-1].dest.port);
            call HashMap.remove(socketid);
            clearsocket(fd);
            sockets[fd-1].state = CLOSED;
            return SUCCESS;
        }
        if(sockets[fd - 1].state == ESTABLISHED || sockets[fd - 1].state == SYN_RCVD){
			sendTCPPacket(fd, FIN);
				
			dbg(TRANSPORT_CHANNEL, "Sending FIN. Going to FIN_WAIT_1\n");
			sockets[fd - 1].state = FIN_WAIT_1;
			return SUCCESS;
        }
        if(sockets[fd - 1].state == CLOSED){
		    sendTCPPacket(fd, FIN);
			sockets[fd - 1].state = LAST_ACK;
			return SUCCESS;
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
    command error_t Transport.release(socket_t fd){
		uint8_t i;
        if(fd == 0 || fd > MAX_NUM_OF_SOCKETS){
            return FAIL;
        }
        return clearsocket(fd);
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
    command error_t Transport.listen(socket_t fd){
        if(fd == 0 || fd > 10){
            return FAIL;
        }

        if(sockets[fd - 1].state == LISTEN){
            dbg(TRANSPORT_CHANNEL, "Shake");
            return SUCCESS;
        }
        else{
            return FAIL;
        }
    }


}