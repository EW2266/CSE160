#ifndef __ROUTING_TABLE_ENTRY__
#define __ROUTING_TABLE_ENTRY__

typedef struct RoutingTableEntry{
    nx_uint16_t src;
	nx_uint16_t seq;
    nx_uint8_t dest;
    nx_uint8_t cost;
    nx_uint8_t next_hop;
};


#endif