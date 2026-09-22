#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PXEditorCanvas;
@class PXEditorViewController;

@protocol PXEditorViewControllerDelegate <NSObject>
/// 完成编辑：返回合成后的导出图（已在后台渲染完毕）。
- (void)editorController:(PXEditorViewController *)controller didFinishWithImage:(UIImage *)image;
/// 取消编辑：源图未被破坏，调用方恢复原流程。
- (void)editorControllerDidCancel:(PXEditorViewController *)controller;
@end

/// 截图编辑器（自持窗口由协调器创建，本控制器作为窗口 rootViewController）。
/// 架构参考 ShellX SSEditorViewController：
/// - 顶部操作栏（取消/裁剪/旋转/撤销/重做/删除/置顶/完成）；
/// - 中部 UIScrollView 缩放容器（底图 + 透明标注画布，捏合缩放、双击 2.5x）；
/// - 底部工具行（15 档工具）+ 颜色/线宽行（贴纸工具时切换为 emoji 行；裁剪模式切换为应用/取消）。
/// 工具全集：平移/画笔/荧光/直线/箭头/方框/实心方/椭圆/实心圆/马赛克/聚光/文字/放大镜/贴纸/图章。
@interface PXEditorViewController : UIViewController

- (instancetype)initWithImage:(UIImage *)sourceImage
                     delegate:(id<PXEditorViewControllerDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
