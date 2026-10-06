#import "PXCaptureTask.h"
#import "../Common/PXConstants.h"
#import "../Common/PXClaimSet.h"
#import "../Common/PXLog.h"
#import "../Output/PXTemporaryFileStore.h"

@interface PXCaptureTask ()
@property (nonatomic, assign, readwrite) PXCaptureState state;
@property (nonatomic, strong, readwrite) PXConfig *configSnapshot;
@property (nonatomic, copy, readwrite) NSString *taskID;
@property (nonatomic, assign, readwrite) PXCaptureMode mode;
@property (nonatomic, assign, readwrite) CGRect capturedScreenBounds;
@property (nonatomic, assign, readwrite) CGFloat capturedScreenScale;
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, strong) PXClaimSet *claimSet;
@end

@implementation PXCaptureTask

- (instancetype)initWithMode:(PXCaptureMode)mode
                      config:(PXConfig *)config
                screenBounds:(CGRect)screenBounds
                 screenScale:(CGFloat)screenScale {
    if (self = [super init]) {
        _taskID = [[NSUUID UUID] UUIDString];
        _mode = mode;
        _configSnapshot = config;
        _capturedScreenBounds = screenBounds;
        _capturedScreenScale = screenScale;
        _state = PXCaptureStateIdle;
        _stateLock = [[NSLock alloc] init];
        _claimSet = [[PXClaimSet alloc] init];
    }
    return self;
}

- (BOOL)transitionToState:(PXCaptureState)target {
    [self.stateLock lock];
    BOOL allowed = PXCaptureStateCanTransition(self.state, target);
    if (allowed) {
        self.state = target;
    }
    [self.stateLock unlock];
    if (!allowed) {
        PXLogWarn(@"illegal transition %@ -> %@ (task %@)",
                  PXStringFromCaptureState(self.state), PXStringFromCaptureState(target), self.taskID);
    }
    return allowed;
}

- (PXCaptureState)currentState {
    [self.stateLock lock];
    PXCaptureState state = self.state;
    [self.stateLock unlock];
    return state;
}

- (BOOL)claimOutputAction:(PXOutputAction)action {
    BOOL claimed = [self.claimSet claimAction:(NSInteger)action];
    if (!claimed) {
        PXLogWarn(@"output action %@ already claimed (task %@)", PXStringFromOutputAction(action), self.taskID);
    }
    return claimed;
}

- (BOOL)isOutputActionClaimed:(PXOutputAction)action {
    return [self.claimSet isActionClaimed:(NSInteger)action];
}

- (void)unclaimOutputAction:(PXOutputAction)action {
    [self.claimSet unclaimAction:(NSInteger)action];
}

- (NSString *)ensureTemporaryDirectory {
    return [PXTemporaryFileStore directoryForTaskID:self.taskID create:YES];
}

- (nullable NSString *)existingTemporaryDirectory {
    return [PXTemporaryFileStore directoryForTaskID:self.taskID create:NO];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<PXCaptureTask %@ mode=%@ state=%@>",
            self.taskID, PXStringFromCaptureMode(self.mode), PXStringFromCaptureState(self.state)];
}

- (void)dealloc {
    // 防御性断引用：任务释放时不应再持有大图。
    _baseImage = nil;
    _resultImage = nil;
}

@end
