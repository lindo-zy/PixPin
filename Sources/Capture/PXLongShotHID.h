#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// IOHIDFloat=double、Boolean=uint8_t；函数表保留运行期解析，不链接私有接口。
typedef struct {
    CFTypeRef (*createClient)(CFAllocatorRef);
    CFTypeRef (*createClientWithType)(CFAllocatorRef, uint32_t, CFDictionaryRef);
    CFTypeRef (*createHand)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                            uint32_t, uint32_t, double, double, double, double, double,
                            uint8_t, uint8_t, uint32_t);
    CFTypeRef (*createFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                              double, double, double, double, double, uint8_t, uint8_t, uint32_t);
    void (*setInteger)(CFTypeRef, uint32_t, int64_t);
    void (*setSender)(CFTypeRef, uint64_t);
    void (*append)(CFTypeRef, CFTypeRef, uint32_t);
    void (*dispatch)(CFTypeRef, CFTypeRef);
} PXLongShotHIDFunctions;

BOOL PXLongShotHIDIsAvailable(const PXLongShotHIDFunctions *functions);
// 返回 +1 客户端，调用方 CFRelease；普通创建失败时尝试 type=0 的客户端。
CFTypeRef PXLongShotCreateHIDClient(const PXLongShotHIDFunctions *functions, BOOL *usedTypedFallback);
// 主线程调用；只证明已调用系统投递接口，不代表目标 App 已接收。
BOOL PXLongShotSendHIDFrame(const PXLongShotHIDFunctions *functions, CFTypeRef client,
                            uint64_t timestamp, CGPoint normalizedPoint,
                            BOOL touching, BOOL transition, BOOL cancelled);
