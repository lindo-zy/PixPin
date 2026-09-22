#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 通用命令式撤销管理器：执行动作后 pushUndo:redo:，undo/redo 反向执行。
/// 栈深限制 50 步，防止长会话内存增长。
@interface PXUndoManager : NSObject

- (BOOL)canUndo;
- (BOOL)canRedo;

/// 动作已执行后调用；undoBlock 撤销该动作，redoBlock 重做。
- (void)pushUndoBlock:(void (^)(void))undoBlock redoBlock:(void (^)(void))redoBlock;

/// pinsImage=YES 的条目强持位图快照（裁剪/旋转烘焙），栈内最多保留 2 条，
/// 超出时从最旧开始淘汰，防止多次烘焙把全尺寸位图累积到 jetsam 阈值。
- (void)pushUndoBlock:(void (^)(void))undoBlock redoBlock:(void (^)(void))redoBlock pinsImage:(BOOL)pinsImage;

- (void)undo;
- (void)redo;
- (void)removeAllActions;

@end

NS_ASSUME_NONNULL_END
