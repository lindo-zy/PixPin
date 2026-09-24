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
/// - 中部 UIScrollView 缩放容器（底图 + 透明标注画布，底图铺满可视区，捏合缩放）；
/// - 底部面板：线宽行（两端细/粗示意图标）/ 工具网格（2×7，右侧彩虹环取色钮，环心显示当前色）/
///   贴纸表情行（仅贴纸工具显示；裁剪模式切换为应用/取消）。
/// 工具全集（2×7 网格，顺序对齐参考图）：画笔/平移/方框/椭圆/箭头/放大镜/直线/
/// 马赛克/文字/实心方/实心圆/聚光/荧光/贴纸。图章不再占用工具位（底层能力保留）。
@interface PXEditorViewController : UIViewController

- (instancetype)initWithImage:(UIImage *)sourceImage
                     delegate:(id<PXEditorViewControllerDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
