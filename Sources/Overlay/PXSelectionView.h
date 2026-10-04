#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"
#import "../Common/PXShellXBridge.h"

NS_ASSUME_NONNULL_BEGIN

@class PXSelectionView;

@protocol PXSelectionViewDelegate <NSObject>
/// 确认选区。action 为用户明确选择的动作（Save/Copy）；
/// PXOutputActionPreviewOnly 表示“使用任务配置的默认动作”。
- (void)selectionView:(PXSelectionView *)view
   didConfirmDisplayRect:(CGRect)displayRect
                 action:(PXOutputAction)action;
- (void)selectionViewDidCancel:(PXSelectionView *)view;
- (void)selectionViewDidRequestEditor:(PXSelectionView *)view displayRect:(CGRect)displayRect;
/// 工具栏“悬浮”按钮：把选区裁剪结果以可拖动悬浮窗常驻屏幕（不执行输出动作）。
- (void)selectionViewDidRequestFloat:(PXSelectionView *)view displayRect:(CGRect)displayRect;
/// 工具栏“长截图”按钮（仅区域模式出现）：以当前选区为采集视口进入自动长截图会话。
- (void)selectionViewDidRequestLong:(PXSelectionView *)view displayRect:(CGRect)displayRect;
/// 工具栏 SHELLX 按钮：把流程外调给 SHELLX（通知发送由协调器负责，本视图不感知可用性）。
- (void)selectionViewDidRequestShellXAction:(PXSelectionView *)view action:(PXShellXAction)action;
@end

/// 区域/冻结/即时模式共用的选区交互层。
/// 基础图是抓屏时刻的归一化快照，坐标转换由协调器使用任务的几何快照完成。
@interface PXSelectionView : UIView

@property (nonatomic, weak, nullable) id<PXSelectionViewDelegate> delegate;
@property (nonatomic, assign, readonly) CGRect selectionRect;

- (instancetype)initWithFrame:(CGRect)frame
                    baseImage:(UIImage *)baseImage
                         mode:(PXCaptureMode)mode
                     delegate:(id<PXSelectionViewDelegate>)delegate;

/// 即时模式预置选区（显示坐标）。
- (void)applyDefaultSelectionRect:(CGRect)rect;

/// 关闭前清理手势与回调，防止销毁后残留调用。
- (void)prepareForDismissal;

@end

NS_ASSUME_NONNULL_END
