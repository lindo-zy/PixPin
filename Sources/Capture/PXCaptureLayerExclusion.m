#import "PXCaptureLayerExclusion.h"
#import "../Common/PXLog.h"
#import <string.h>
#import <dispatch/dispatch.h>

// Core Animation 的捕获排除位；只对本会话自有图层生效，保留其他标记。
static const uint64_t PXCaptureExcludedMask = 0x12;
static const char *PXUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}
static NSMethodSignature *PXMaskSignature(id layer, BOOL setter) {
    SEL selector = NSSelectorFromString(setter ? @"setDisableUpdateMask:" : @"disableUpdateMask");
    if (![layer respondsToSelector:selector]) return nil;
    NSMethodSignature *sig = [layer methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != (setter ? 3 : 2)) return nil;
    const char *type = PXUnqualifiedType(setter ? [sig getArgumentTypeAtIndex:2] : sig.methodReturnType);
    if (!strchr("ILQ", type[0]) || type[1] != '\0') return nil;
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(uint64_t) || (setter && strcmp(sig.methodReturnType, @encode(void)))) return nil;
    return sig;
}
static uint64_t PXReadMask(id layer) {
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:PXMaskSignature(layer, NO)];
    call.target = layer; call.selector = NSSelectorFromString(@"disableUpdateMask");
    [call invoke];
    uint64_t mask = 0; [call getReturnValue:&mask]; return mask;
}
static void PXWriteMask(id layer, uint64_t mask) {
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:PXMaskSignature(layer, YES)];
    call.target = layer; call.selector = NSSelectorFromString(@"setDisableUpdateMask:");
    [call setArgument:&mask atIndex:2]; [call invoke];
}
static void PXRestoreCaptureMasks(NSArray<NSDictionary *> *records) {
    for (NSDictionary *record in records) {
        @try {
            id layer = record[@"layer"];
            uint64_t current = PXReadMask(layer), original = [record[@"original"] unsignedLongLongValue];
            PXWriteMask(layer, (current & ~PXCaptureExcludedMask) | (original & PXCaptureExcludedMask));
        } @catch (NSException *exception) {
            PXLogWarn(@"long shot layer exclusion cleanup failed (%@)", exception.name);
        }
    }
}
@interface PXCaptureLayerExclusion ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *records;
@property (nonatomic, readwrite, getter=isActive) BOOL active;
@end
@implementation PXCaptureLayerExclusion
+ (instancetype)beginWithLayers:(NSArray *)layers {
    NSParameterAssert(NSThread.isMainThread);
    if (!layers.count) return nil;
    PXCaptureLayerExclusion *guard = [self new]; guard.records = [NSMutableArray array];
    @try {
        for (id layer in [NSOrderedSet orderedSetWithArray:layers]) {
            if (!PXMaskSignature(layer, NO) || !PXMaskSignature(layer, YES)) {
                [guard invalidate]; return nil;
            }
            uint64_t original = PXReadMask(layer);
            [guard.records addObject:@{@"layer":layer, @"original":@(original)}];
            PXWriteMask(layer, original | PXCaptureExcludedMask);
            if (PXReadMask(layer) != (original | PXCaptureExcludedMask)) {
                [guard invalidate]; return nil;
            }
        }
        guard.active = YES;
        return guard;
    } @catch (NSException *exception) {
        PXLogWarn(@"long shot layer exclusion setup failed (%@)", exception.name);
        [guard invalidate]; return nil;
    }
}
- (void)invalidate {
    NSParameterAssert(NSThread.isMainThread);
    self.active = NO;
    // 仅恢复自己拥有的捕获位，保留会话期间其他模块改动的非捕获位。
    PXRestoreCaptureMasks(self.records);
    [self.records removeAllObjects];
}
- (void)dealloc {
    if (!_records.count) return;
    // 正常会话显式清理；异常释放兜底也只在主线程恢复图层。
    NSArray *records = [_records copy];
    if (NSThread.isMainThread) PXRestoreCaptureMasks(records);
    else dispatch_async(dispatch_get_main_queue(), ^{ PXRestoreCaptureMasks(records); });
}
@end
