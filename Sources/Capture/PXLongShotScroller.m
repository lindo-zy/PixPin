#import "PXLongShotScroller.h"
#import "PXLongShotHID.h"
#import "../Common/PXLog.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <mach/mach_time.h>
#import <QuartzCore/QuartzCore.h>

typedef CFTypeRef PXHIDClientRef;
static PXLongShotHIDFunctions PXHIDFunctions;

static id PXLongShotReadObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

@interface PXLongShotScroller () {
    PXHIDClientRef _client;
}
@property (nonatomic, copy, readwrite) NSString *availabilityError;
@property (nonatomic, copy, readwrite) NSString *targetApplicationIdentifier;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, copy) void (^completion)(BOOL);
@property (nonatomic, assign) PXLongShotScrollPlan plan;
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) BOOL fingerDown;
@end

@implementation PXLongShotScroller

- (instancetype)init {
    NSParameterAssert([NSThread isMainThread]);
    if (self = [super init]) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            // 句柄驻进程；函数指针使用期不可 dlclose。未导出时安全拒绝自动滚动。
            void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
            if (!handle) return;
            PXHIDFunctions.createClient = dlsym(handle, "IOHIDEventSystemClientCreate");
            PXHIDFunctions.createClientWithType = dlsym(handle, "IOHIDEventSystemClientCreateWithType");
            PXHIDFunctions.createHand = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
            PXHIDFunctions.createFinger = dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
            PXHIDFunctions.setInteger = dlsym(handle, "IOHIDEventSetIntegerValue");
            PXHIDFunctions.setSender = dlsym(handle, "IOHIDEventSetSenderID");
            PXHIDFunctions.append = dlsym(handle, "IOHIDEventAppendEvent");
            PXHIDFunctions.dispatch = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
        });
        if (!PXLongShotHIDIsAvailable(&PXHIDFunctions)) {
            _availabilityError = @"当前系统的自动滚动接口不可用";
        } else {
            BOOL typedFallback = NO;
            _client = PXLongShotCreateHIDClient(&PXHIDFunctions, &typedFallback);
            if (!_client) _availabilityError = @"自动滚动事件通道创建失败";
            PXLogInfo(@"long shot scroll HID client (created=%d typedFallback=%d)", _client != NULL, typedFallback);
        }
        id application = PXLongShotReadObject(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication");
        id identifier = PXLongShotReadObject(application, @"bundleIdentifier");
        if ([identifier isKindOfClass:NSString.class] && [identifier length] > 0) {
            _targetApplicationIdentifier = [identifier copy];
        } else if (!_availabilityError) {
            _availabilityError = @"请先打开需要长截图的 App";
        }
        if (!_availabilityError && ![self targetApplicationIsCurrent]) {
            _availabilityError = @"当前页面不能开始自动滚动";
        }
    }
    return self;
}

- (BOOL)targetApplicationIsCurrent {
    NSParameterAssert([NSThread isMainThread]);
    if (!self.targetApplicationIdentifier) return NO;
    id manager = PXLongShotReadObject(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance");
    SEL lockedSelector = NSSelectorFromString(@"isUILocked");
    if (!manager || ![manager respondsToSelector:lockedSelector]) return NO;
    @try {
        if (((BOOL (*)(id, SEL))objc_msgSend)(manager, lockedSelector)) return NO;
    } @catch (__unused NSException *exception) { return NO; }
    id application = PXLongShotReadObject(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication");
    id identifier = PXLongShotReadObject(application, @"bundleIdentifier");
    return [identifier isKindOfClass:NSString.class] && [identifier isEqual:self.targetApplicationIdentifier];
}

- (BOOL)pxSendPoint:(CGPoint)point touching:(BOOL)touching transition:(BOOL)transition cancelled:(BOOL)cancelled {
    if (!_client) return NO;
    UIScreen *screen = UIScreen.mainScreen;
    CGPoint native = [screen.coordinateSpace convertPoint:point toCoordinateSpace:screen.fixedCoordinateSpace];
    CGRect bounds = screen.fixedCoordinateSpace.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return NO;
    double x = MIN(MAX((native.x - bounds.origin.x) / bounds.size.width, 0.0), 1.0);
    double y = MIN(MAX((native.y - bounds.origin.y) / bounds.size.height, 0.0), 1.0);
    return PXLongShotSendHIDFrame(&PXHIDFunctions, _client, mach_absolute_time(),
                                   CGPointMake(x, y), touching, transition, cancelled);
}

- (void)scrollWithPlan:(PXLongShotScrollPlan)plan completion:(void (^)(BOOL))completion {
    NSParameterAssert([NSThread isMainThread]);
    if (self.displayLink || self.availabilityError || ![self targetApplicationIsCurrent]) {
        completion(NO);
        return;
    }
    self.plan = plan;
    self.lastPoint = plan.start;
    self.completion = completion;
    PXLogInfo(@"long shot scroll begin (target=%@ start=%@ end=%@)", self.targetApplicationIdentifier,
              NSStringFromCGPoint(plan.start), NSStringFromCGPoint(plan.end));
    if (![self pxSendPoint:plan.start touching:YES transition:YES cancelled:NO]) {
        PXLogWarn(@"long shot scroll touch-down failed (target=%@)", self.targetApplicationIdentifier);
        [self pxFinish:NO];
        return;
    }
    self.fingerDown = YES;
    self.startedAt = CACurrentMediaTime();
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(pxTick:)];
    self.displayLink.preferredFramesPerSecond = 60;
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)pxTick:(CADisplayLink *)link {
    if (![self targetApplicationIsCurrent]) { [self pxFinish:NO]; return; }
    CFTimeInterval elapsed = CACurrentMediaTime() - self.startedAt;
    CGFloat t = MIN(MAX(elapsed / 0.50, 0.0), 1.0);
    CGFloat p = t * t * (3.0 - 2.0 * t); // 两端零速度，随后按住 0.12s，抑制惯性甩屏。
    CGPoint point = CGPointMake(self.plan.start.x, self.plan.start.y + (self.plan.end.y - self.plan.start.y) * p);
    self.lastPoint = point;
    if (![self pxSendPoint:point touching:YES transition:NO cancelled:NO]) { [self pxFinish:NO]; return; }
    if (elapsed >= 0.62) [self pxFinish:YES];
}

- (void)pxFinish:(BOOL)completed {
    [self.displayLink invalidate];
    self.displayLink = nil;
    if (self.fingerDown) {
        BOOL lifted = [self pxSendPoint:self.lastPoint touching:NO transition:YES cancelled:!completed];
        completed = completed && lifted;
        self.fingerDown = NO;
    }
    void (^completion)(BOOL) = self.completion;
    self.completion = nil;
    if (completion) {
        PXLogInfo(@"long shot scroll finished (target=%@ completed=%d)", self.targetApplicationIdentifier, completed);
        completion(completed);
    }
}

- (void)cancel {
    NSParameterAssert([NSThread isMainThread]);
    [self pxFinish:NO];
}

- (void)dealloc {
    NSAssert(!self.fingerDown && !self.displayLink, @"automatic scroll must be cancelled before release");
    if (_client) CFRelease(_client);
}

@end
