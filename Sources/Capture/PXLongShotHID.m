#import "PXLongShotHID.h"
#import <math.h>

// 来自 ShellX 3.1.1 的发送函数 0x16D188；本地旧 IOKit 头的字段布局不同，
// 不使用其枚举。父事件是屏幕触摸集合，实际坐标及按下状态由手指子事件提供。
static const uint32_t PXHIDDigitizerCollection = 0xB0014;
static const uint32_t PXHIDDigitizerDisplayIntegrated = 0xB0019;
static const uint64_t PXHIDTouchSender = 0x8000000817319372ULL;

BOOL PXLongShotHIDIsAvailable(const PXLongShotHIDFunctions *f) {
    return f && (f->createClient || f->createClientWithType) && f->createHand && f->createFinger &&
        f->setInteger && f->setSender && f->append && f->dispatch;
}

CFTypeRef PXLongShotCreateHIDClient(const PXLongShotHIDFunctions *f, BOOL *usedTypedFallback) {
    if (usedTypedFallback) *usedTypedFallback = NO;
    if (!PXLongShotHIDIsAvailable(f)) return NULL;
    CFTypeRef client = NULL;
    @try {
        if (f->createClient) client = f->createClient(kCFAllocatorDefault);
    } @catch (__unused NSException *exception) {}
    if (!client && f->createClientWithType) {
        @try {
            client = f->createClientWithType(kCFAllocatorDefault, 0, NULL);
            if (client && usedTypedFallback) *usedTypedFallback = YES;
        } @catch (__unused NSException *exception) {}
    }
    return client;
}

BOOL PXLongShotSendHIDFrame(const PXLongShotHIDFunctions *f, CFTypeRef client,
                            uint64_t timestamp, CGPoint point,
                            BOOL touching, BOOL transition, BOOL cancelled) {
    if (!client || !PXLongShotHIDIsAvailable(f) || !isfinite(point.x) || !isfinite(point.y)) return NO;
    uint32_t mask = transition ? 0x03 : 0x04; // Range|Touch / Position，与 ShellX 相同。
    if (cancelled) mask |= 0x80;
    CFTypeRef hand = NULL, finger = NULL;
    @try {
        hand = f->createHand(kCFAllocatorDefault, timestamp, 3, 0, 0, 0x01, 0,
                              0, 0, 0, 0, 0, 1, 0, 0);
        if (!hand) return NO;
        f->setInteger(hand, PXHIDDigitizerCollection, 1);
        f->setInteger(hand, PXHIDDigitizerDisplayIntegrated, 1);
        finger = f->createFinger(kCFAllocatorDefault, timestamp, 1, 2, mask,
                                  MIN(MAX(point.x, 0.0), 1.0), MIN(MAX(point.y, 0.0), 1.0),
                                  0, 0, 0, touching, touching, 0);
        if (!finger) return NO;
        f->append(hand, finger, 0);
        f->setSender(hand, PXHIDTouchSender);
        f->dispatch(client, hand);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    } @finally {
        if (finger) CFRelease(finger);
        if (hand) CFRelease(hand);
    }
}
