#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PXEditorViewController;

@protocol PXEditorViewControllerDelegate <NSObject>
/// 完成编辑：返回合成后的导出图（已在后台渲染完毕）。
- (void)editorController:(PXEditorViewController *)controller didFinishWithImage:(UIImage *)image;
/// 取消编辑：源图未被破坏，调用方恢复原流程。
- (void)editorControllerDidCancel:(PXEditorViewController *)controller;
@end

/// 截图编辑器（自持窗口由协调器创建，本控制器作为窗口 rootViewController）。
/// 第一版工具集：画笔/直线/箭头/方框/椭圆/荧光笔/马赛克/文字 + 6 色 + 线宽 + 撤销/重做。
@interface PXEditorViewController : UIViewController

- (instancetype)initWithImage:(UIImage *)sourceImage
                     delegate:(id<PXEditorViewControllerDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
