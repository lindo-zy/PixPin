#import "PXClaimSet.h"

@interface PXClaimSet ()
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *claimed;
@end

@implementation PXClaimSet

- (instancetype)init {
    if (self = [super init]) {
        _lock = [[NSLock alloc] init];
        _claimed = [[NSMutableSet alloc] init];
    }
    return self;
}

- (BOOL)claimAction:(NSInteger)action {
    [self.lock lock];
    NSNumber *key = @(action);
    BOOL claimed = ![self.claimed containsObject:key];
    if (claimed) {
        [self.claimed addObject:key];
    }
    [self.lock unlock];
    return claimed;
}

- (void)unclaimAction:(NSInteger)action {
    [self.lock lock];
    [self.claimed removeObject:@(action)];
    [self.lock unlock];
}

- (BOOL)isActionClaimed:(NSInteger)action {
    [self.lock lock];
    BOOL claimed = [self.claimed containsObject:@(action)];
    [self.lock unlock];
    return claimed;
}

- (void)reset {
    [self.lock lock];
    [self.claimed removeAllObjects];
    [self.lock unlock];
}

@end
