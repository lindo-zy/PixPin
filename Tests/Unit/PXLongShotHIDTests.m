#import <Foundation/Foundation.h>
#import <math.h>
#import "../../Sources/Capture/PXLongShotHID.h"

// 捕获真实适配器传给 IOKit 的参数；CF 所有权仍通过真实 CFRelease 回收。
static NSInteger PXHIDLiveEvents;
static BOOL PXHIDFailHand, PXHIDFailFinger, PXHIDThrowDispatch, PXHIDFailClient, PXHIDFailTypedClient;
static NSInteger PXHIDClientCalls, PXHIDTypedClientCalls;
static uint32_t PXHIDLastClientType;
static NSMutableArray<NSDictionary *> *PXHIDPackets;

@interface PXHIDTestEvent : NSObject
@property (nonatomic, strong) NSDictionary *arguments;
@property (nonatomic, strong) NSMutableDictionary *fields;
@property (nonatomic, strong) PXHIDTestEvent *child;
@property (nonatomic, assign) uint64_t sender;
@end
@implementation PXHIDTestEvent
- (instancetype)init {
    if (self = [super init]) { PXHIDLiveEvents++; _fields = [NSMutableDictionary dictionary]; }
    return self;
}
- (void)dealloc { PXHIDLiveEvents--; }
@end

static CFTypeRef PXHIDTestClient(CFAllocatorRef allocator) {
    PXHIDClientCalls++;
    return PXHIDFailClient ? NULL : CFBridgingRetain([NSObject new]);
}
static CFTypeRef PXHIDTestTypedClient(CFAllocatorRef allocator, uint32_t type, CFDictionaryRef options) {
    PXHIDTypedClientCalls++;
    PXHIDLastClientType = type;
    return PXHIDFailTypedClient ? NULL : CFBridgingRetain([NSObject new]);
}
static CFTypeRef PXHIDTestHand(CFAllocatorRef allocator, uint64_t timestamp, uint32_t type,
    uint32_t index, uint32_t identity, uint32_t mask, uint32_t buttons,
    double x, double y, double z, double pressure, double barrel, uint8_t range, uint8_t touch, uint32_t options) {
    if (PXHIDFailHand) return NULL;
    PXHIDTestEvent *event = [PXHIDTestEvent new];
    event.arguments = @{@"time": @(timestamp), @"type": @(type), @"index": @(index), @"identity": @(identity),
        @"mask": @(mask), @"buttons": @(buttons), @"x": @(x), @"y": @(y), @"z": @(z),
        @"pressure": @(pressure), @"barrel": @(barrel), @"range": @(range), @"touch": @(touch), @"options": @(options)};
    return CFBridgingRetain(event);
}
static CFTypeRef PXHIDTestFinger(CFAllocatorRef allocator, uint64_t timestamp, uint32_t index,
    uint32_t identity, uint32_t mask, double x, double y, double z, double pressure, double twist,
    uint8_t range, uint8_t touch, uint32_t options) {
    if (PXHIDFailFinger) return NULL;
    PXHIDTestEvent *event = [PXHIDTestEvent new];
    event.arguments = @{@"time": @(timestamp), @"index": @(index), @"identity": @(identity), @"mask": @(mask),
        @"x": @(x), @"y": @(y), @"z": @(z), @"pressure": @(pressure), @"twist": @(twist),
        @"range": @(range), @"touch": @(touch), @"options": @(options)};
    return CFBridgingRetain(event);
}
static void PXHIDTestInteger(CFTypeRef ref, uint32_t field, int64_t value) {
    ((__bridge PXHIDTestEvent *)ref).fields[@(field)] = @(value);
}
static void PXHIDTestSender(CFTypeRef ref, uint64_t sender) {
    ((__bridge PXHIDTestEvent *)ref).sender = sender;
}
static void PXHIDTestAppend(CFTypeRef hand, CFTypeRef finger, uint32_t options) {
    ((__bridge PXHIDTestEvent *)hand).child = (__bridge PXHIDTestEvent *)finger;
}
static void PXHIDTestDispatch(CFTypeRef client, CFTypeRef ref) {
    if (PXHIDThrowDispatch) [NSException raise:@"PXHIDTestDispatch" format:@"injected failure"];
    PXHIDTestEvent *hand = (__bridge PXHIDTestEvent *)ref;
    [PXHIDPackets addObject:@{@"hand": hand.arguments, @"finger": hand.child.arguments,
                             @"fields": [hand.fields copy], @"sender": @(hand.sender)}];
}

NSInteger PXRunLongShotHIDTests(NSInteger *checkCount) {
    NSInteger checks = 0, failures = 0;
#define HID_CHECK(condition, name) do { checks++; if (!(condition)) { failures++; \
    printf("  FAIL: %s (line %d)\n", name, __LINE__); } else printf("  ok: %s\n", name); } while (0)
    printf("[long shot HID packet contract and ownership]\n");
    PXLongShotHIDFunctions f = {PXHIDTestClient, PXHIDTestTypedClient, PXHIDTestHand, PXHIDTestFinger,
                                PXHIDTestInteger, PXHIDTestSender, PXHIDTestAppend, PXHIDTestDispatch};
    PXHIDPackets = [NSMutableArray array];
    BOOL typed = YES;
    CFTypeRef client = PXLongShotCreateHIDClient(&f, &typed);
    HID_CHECK(client && !typed && PXHIDClientCalls == 1 && PXHIDTypedClientCalls == 0,
              "standard HID client is used without creating a second client");
    const BOOL touches[] = {YES, YES, YES, NO};
    const BOOL transitions[] = {YES, NO, NO, YES};
    const double positions[] = {0.8, 0.5, 0.2, 0.2};
    for (NSInteger i = 0; i < 4; i++) {
        HID_CHECK(PXLongShotSendHIDFrame(&f, client, 123 + i, CGPointMake(0.4, positions[i]),
                                        touches[i], transitions[i], NO), "down/move/up packet dispatches");
        HID_CHECK(PXHIDLiveEvents == 0, "parent and child events release after dispatch");
    }
    // 独立的 ShellX 3.1.1 抓取参数契约，覆盖旧代码会违反的集合/父触摸/sender/身份字段。
    NSDictionary *packet = PXHIDPackets.firstObject;
    NSDictionary *hand = packet[@"hand"], *finger = packet[@"finger"], *fields = packet[@"fields"];
    HID_CHECK([fields[@(0xB0014)] intValue] == 1 && [fields[@(0xB0019)] intValue] == 1,
              "parent is a display-integrated digitizer collection");
    HID_CHECK([hand[@"range"] intValue] == 1 && [hand[@"touch"] intValue] == 0 &&
              [hand[@"x"] doubleValue] == 0 && [hand[@"y"] doubleValue] == 0 &&
              [hand[@"mask"] intValue] == 1 && [hand[@"type"] intValue] == 3,
              "parent is a neutral collection rather than a second pressed finger");
    HID_CHECK([packet[@"sender"] unsignedLongLongValue] == 0x8000000817319372ULL,
              "touch sender matches the working ShellX dispatcher");
    HID_CHECK([finger[@"index"] intValue] == 1 && [finger[@"identity"] intValue] == 2 &&
              [finger[@"pressure"] doubleValue] == 0 && [finger[@"options"] intValue] == 0,
              "single-finger identity and pressure match ShellX");
    for (NSInteger i = 0; i < 4; i++) {
        NSDictionary *sample = PXHIDPackets[i][@"finger"];
        HID_CHECK([sample[@"mask"] intValue] == (transitions[i] ? 3 : 4) &&
                  [sample[@"range"] boolValue] == touches[i] && [sample[@"touch"] boolValue] == touches[i] &&
                  [sample[@"y"] doubleValue] == positions[i] && [sample[@"x"] doubleValue] == 0.4 &&
                  [sample[@"time"] unsignedLongLongValue] == (uint64_t)(123 + i),
                  "finger stream preserves coordinates, phase and timestamp through lift");
    }
    HID_CHECK(PXLongShotSendHIDFrame(&f, client, 130, CGPointMake(0.4, 0.2), NO, YES, YES),
              "cancel dispatches a final lifted finger");
    finger = PXHIDPackets.lastObject[@"finger"];
    HID_CHECK([finger[@"mask"] intValue] == 0x83 && ![finger[@"touch"] boolValue] && ![finger[@"range"] boolValue],
              "cancel keeps Range|Touch transitions and adds Cancel without a pressed child");
    NSUInteger dispatched = PXHIDPackets.count;
    PXHIDFailHand = YES;
    HID_CHECK(!PXLongShotSendHIDFrame(&f, client, 140, CGPointMake(0.4, 0.2), YES, YES, NO) &&
              PXHIDLiveEvents == 0 && PXHIDPackets.count == dispatched, "failed parent allocation sends nothing");
    PXHIDFailHand = NO; PXHIDFailFinger = YES;
    HID_CHECK(!PXLongShotSendHIDFrame(&f, client, 140, CGPointMake(0.4, 0.2), YES, YES, NO) &&
              PXHIDLiveEvents == 0 && PXHIDPackets.count == dispatched, "failed child allocation releases the parent");
    PXHIDFailFinger = NO; PXHIDThrowDispatch = YES;
    HID_CHECK(!PXLongShotSendHIDFrame(&f, client, 140, CGPointMake(0.4, 0.2), YES, YES, NO) &&
              PXHIDLiveEvents == 0, "dispatch exception releases both events and reports failure");
    PXHIDThrowDispatch = NO;
    HID_CHECK(!PXLongShotSendHIDFrame(&f, NULL, 140, CGPointMake(0.4, 0.2), YES, YES, NO) &&
              !PXLongShotSendHIDFrame(&f, client, 140, CGPointMake(NAN, 0.2), YES, YES, NO),
              "missing client and invalid coordinates cannot dispatch");
    HID_CHECK(PXLongShotSendHIDFrame(&f, client, 140, CGPointMake(-0.5, 1.5), YES, YES, NO),
              "finite outside-screen coordinates are safely clamped");
    finger = PXHIDPackets.lastObject[@"finger"];
    HID_CHECK([finger[@"x"] doubleValue] == 0 && [finger[@"y"] doubleValue] == 1, "coordinate clamp reaches screen edges");
    CFRelease(client);

    PXHIDFailClient = YES;
    client = PXLongShotCreateHIDClient(&f, &typed);
    HID_CHECK(client && typed && PXHIDTypedClientCalls == 1 && PXHIDLastClientType == 0,
              "failed standard client falls back to ShellX type zero");
    if (client) CFRelease(client);
    f.createClient = NULL;
    client = PXLongShotCreateHIDClient(&f, &typed);
    HID_CHECK(client && typed, "missing standard constructor still allows typed-client systems");
    if (client) CFRelease(client);
    PXHIDFailTypedClient = YES;
    HID_CHECK(!PXLongShotCreateHIDClient(&f, &typed) && !typed, "both constructor failures return a clean failure");
    f.createClientWithType = NULL;
    HID_CHECK(!PXLongShotHIDIsAvailable(&f), "missing client constructors reject unsupported systems");
    f.createClient = PXHIDTestClient; f.setInteger = NULL;
    HID_CHECK(!PXLongShotHIDIsAvailable(&f), "missing collection setter rejects incomplete event support");
    HID_CHECK(PXHIDLiveEvents == 0, "all injected error paths leave no live HID event objects");
    PXHIDPackets = nil;
    *checkCount = checks;
#undef HID_CHECK
    return failures;
}
