#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class PXEditorCanvas;
@class PXEditorViewController;

@protocol PXEditorViewControllerDelegate <NSObject>
/// 完成编辑：返回合成后的导出图（已在后台渲染完毕）。
- (void)editorController:(PXEditorViewController *)controller didFinishWithImage:(UIImage *)image action:(PXOutputAction)action;
/// 取消编辑：源图未被破坏，调用方恢复原流程。
- (void)editorControllerDidCancel:(PXEditorViewController *)controller;
@end

/// 区域图片使用圆角卡片；全屏标记使用冻结整屏底图与悬浮多排面板。
/// 两种布局共用完整工具、文档、撤销栈和输出流程。
@interface PXEditorViewController : UIViewController

/// 在加载 view 前设置。
@property (nonatomic, assign) BOOL fullscreenMarkup;
@property (nonatomic, strong, nullable) UIImage *backdropImage;

- (instancetype)initWithImage:(UIImage *)sourceImage
                     delegate:(id<PXEditorViewControllerDelegate>)delegate;

/// 销毁前由协调器调用：断开 view→手势→控制器的引用环并清理画布（可重复调用）。
- (void)prepareForDismissal;

@end

NS_ASSUME_NONNULL_END
