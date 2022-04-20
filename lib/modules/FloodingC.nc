/**
 * This class provides the flooding functionality for nodes on the network.
 *
 * @author Chris DeSoto
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components FloodingP;
    Flooding = FloodingP;

    components new SimpleSendC(AM_PACK);
    FloodingP.Sender -> SimpleSendC;
    
    components new MapListC(uint16_t, uint16_t, 20, 20);
    FloodingP.PacketsReceived -> MapListC;
}
