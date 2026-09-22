#import <UIKit/UIKit.h>
#import "PXAnnotation.h"
#import "PXEditorDocument.h"

NS_ASSUME_NONNULL_BEGIN

@class PXEditorCanvas;

@protocol PXEditorCanvasDelegate <NSObject>/// 标注增删/变换/撤销状态变化（刷新撤销按钮等）。
- (void)canvasDidChangeContent:(PXEditorCanvas *)canvas;
/// 选中标注变化（刷新删除/置顶按钮）。
- (void)canvasDidChangeSelection:(PXEditorCanvas *)canvas;
/// 裁剪/旋转烘焙后画布尺寸变化（刷新滚动容器 contentSize）。
- (void)canvasDidChangeGeometry:(PXEditorCanvas *)canvas;
/// 文字输入开始/结束（调用方禁用滚动缩放，避免键盘期视图漂移）。
- (void)canvasDidStartTextInput:(PXEditorCanvas *)canvas;
- (void)canvasDidEndTextInput:(PXEditorCanvas *)canvas;
/// 文字输入框位置变化（键盘遮挡时调用方滚动让位）。
- (void)canvas:(PXEditorCanvas *)canvas didUpdateTextInputFrame:(CGRect)canvasFrame;
/// 键盘多次重试仍无法唤起（SpringBoard 偶发）；调用方应改走弹窗输入兜底。
- (void)canvasKeyboardUnavailable:(PXEditorCanvas *)canvas pendingTextPoint:(CGPoint)canvasPoint;
@end

/// 编辑画布：透明覆盖层，bounds == 源图点空间（标注坐标即本视图坐标，恒等变换）。
/// 交互模型参考 ShellX SSCustomDrawingView：
/// - 绘制工具下单指绘制、双指交由滚动容器平移/缩放；
/// - 点击标注选中，选中后单指拖动、捏合缩放（贴纸另支持旋转）；
/// - 文字工具点击处内联 UITextView 输入；
/// - 放大镜/贴纸/图章点击放置；
/// - 裁剪模式 8 手柄调整，应用即烘焙（底图替换，标注重映射，可撤销）。
@interface PXEditorCanvas : UIView

@property (nonatomic, weak, nullable) id<PXEditorCanvasDelegate> delegate;
@property (nonatomic, strong, readonly) PXEditorDocument *document;

@property (nonatomic, assign) PXAnnotationType currentTool;
@property (nonatomic, strong) UIColor *currentColor;
@property (nonatomic, assign) CGFloat currentLineWidth;
@property (nonatomic, assign) PXAnnotationFillStyle currentFillStyle;
/// 贴纸工具放置的内容（emoji）。
@property (nonatomic, copy, nullable) NSString *currentStickerText;
/// 文字工具的默认字号（图片点空间）。
@property (nonatomic, assign) CGFloat currentTextFontSize;

@property (nonatomic, strong, readonly, nullable) PXAnnotation *selectedAnnotation;
@property (nonatomic, assign, readonly) BOOL cropActive;
@property (nonatomic, assign, readonly) BOOL textEditing;

- (instancetype)initWithFrame:(CGRect)frame document:(PXEditorDocument *)document;

- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)undo;
- (void)redo;

- (void)deleteSelectedAnnotation;
- (void)bringSelectedAnnotationToFront;

/// 马赛克预览底图（异步生成，完成后自动重绘）。
- (void)requestPixelatedPreview;

/// 裁剪：进入/放弃/应用（应用成功返回 YES 并回调 canvasDidChangeGeometry）。
- (void)beginCrop;
- (void)cancelCrop;
- (BOOL)applyCrop;

/// 顺时针旋转 90°（烘焙，可撤销）。
- (BOOL)rotateImage90Clockwise;

/// 让本画布的 tap 让位于外部双击手势（双击缩放）。
- (void)requireTapToFail:(UIGestureRecognizer *)otherGesture;

/// 兜底入口：键盘不可用时由弹窗输入后直接落字（画布坐标）。
- (void)placeTextAnnotationWithText:(NSString *)text atCanvasPoint:(CGPoint)point;

/// 提交进行中的文字输入（无进行中输入时为空操作）。顶栏动作前调用，避免丢字。
- (void)commitActiveText;

- (void)prepareForDismissal;

@end

NS_ASSUME_NONNULL_END
