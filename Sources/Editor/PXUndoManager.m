#import "PXUndoManager.h"

static const NSUInteger PXUndoStackLimit = 50;
static const NSUInteger PXMaxImagePinnedEntries = 2;

@interface PXUndoManager ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *undoStack;   // undoBlock/redoBlock/pinsImage
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *redoStack;
@end

@implementation PXUndoManager

- (instancetype)init {
    if (self = [super init]) {
        _undoStack = [[NSMutableArray alloc] init];
        _redoStack = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)canUndo {
    return self.undoStack.count > 0;
}

- (BOOL)canRedo {
    return self.redoStack.count > 0;
}

- (void)pushUndoBlock:(void (^)(void))undoBlock redoBlock:(void (^)(void))redoBlock {
    [self pushUndoBlock:undoBlock redoBlock:redoBlock pinsImage:NO];
}

- (void)pushUndoBlock:(void (^)(void))undoBlock redoBlock:(void (^)(void))redoBlock pinsImage:(BOOL)pinsImage {
    if (!undoBlock || !redoBlock) return;
    NSDictionary *action = @{ @"undo": undoBlock, @"redo": redoBlock, @"pinsImage": @(pinsImage) };
    [self.undoStack addObject:action];
    if (self.undoStack.count > PXUndoStackLimit) {
        [self.undoStack removeObjectAtIndex:0];
    }
    if (pinsImage) {
        [self pxTrimImagePinnedEntries];
    }
    [self.redoStack removeAllObjects];   // 新动作使重做链失效
}

- (void)pxTrimImagePinnedEntries {
    NSInteger pinned = 0;
    for (NSDictionary *action in self.undoStack) {
        if ([action[@"pinsImage"] boolValue]) pinned++;
    }
    while (pinned > (NSInteger)PXMaxImagePinnedEntries) {
        BOOL removed = NO;
        for (NSUInteger i = 0; i < self.undoStack.count; i++) {
            if ([self.undoStack[i][@"pinsImage"] boolValue]) {
                [self.undoStack removeObjectAtIndex:i];
                pinned--;
                removed = YES;
                break;
            }
        }
        if (!removed) break;
    }
}

- (void)undo {
    if (self.undoStack.count == 0) return;
    NSDictionary *action = [self.undoStack lastObject];
    [self.undoStack removeLastObject];
    void (^undoBlock)(void) = action[@"undo"];
    if (undoBlock) undoBlock();
    [self.redoStack addObject:action];
}

- (void)redo {
    if (self.redoStack.count == 0) return;
    NSDictionary *action = [self.redoStack lastObject];
    [self.redoStack removeLastObject];
    void (^redoBlock)(void) = action[@"redo"];
    if (redoBlock) redoBlock();
    [self.undoStack addObject:action];
}

- (void)removeAllActions {
    [self.undoStack removeAllObjects];
    [self.redoStack removeAllObjects];
}

@end
