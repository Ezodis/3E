#import "MidiOutput.h"

@implementation Strip3MidiOutput {
    MIDIClientRef _client;
    MIDIPortRef _port;
    MIDIEndpointRef _destination;
}
- (instancetype)init {
    if((self=[super init])) {
        MIDIClientCreate(CFSTR("Strip3£"),NULL,NULL,&_client);
        MIDIOutputPortCreate(_client,CFSTR("Strip3£ output"),&_port);
        if(MIDIGetNumberOfDestinations()>0) _destination=MIDIGetDestination(0);
    }
    return self;
}
- (void)sendStatus:(UInt8)status data1:(NSInteger)data1 data2:(NSInteger)data2 {
    if(!_destination) return;
    Byte bytes[3]={status,(Byte)MAX(0,MIN(127,data1)),(Byte)MAX(0,MIN(127,data2))};
    Byte packetBuffer[sizeof(MIDIPacketList)+sizeof(MIDIPacket)]; MIDIPacketList *list=(MIDIPacketList *)packetBuffer;
    MIDIPacket *packet=MIDIPacketListInit(list); packet=MIDIPacketListAdd(list,sizeof(packetBuffer),packet,0,3,bytes); if(packet) MIDISend(_port,_destination,list);
}
- (void)noteOn:(NSInteger)note velocity:(NSInteger)velocity channel:(NSInteger)channel { [self sendStatus:0x90|((Byte)MAX(1,MIN(16,channel))-1) data1:note data2:velocity]; }
- (void)noteOff:(NSInteger)note channel:(NSInteger)channel { [self sendStatus:0x80|((Byte)MAX(1,MIN(16,channel))-1) data1:note data2:0]; }
- (void)dealloc { if(_port) MIDIPortDispose(_port); if(_client) MIDIClientDispose(_client); }
@end
