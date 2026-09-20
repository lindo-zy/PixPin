#import <UIKit/UIKit.h>
#import "PXAnnotation.h"
#import "PXEditorDocument.h"

NS_ASSUME_NONNULL_BEGIN

@class PXEditorCanvas;

@protocol PXEditorCanvasDelegate <NSObject>
/// 内容变化（标注增删/撤销状态变化），用于刷新撤销按钮可用性。
- (void)canvasDidChangeContent:(PXEditorCanvas *)canvas;
/// 用户点击文字工具的目标位置（视图坐标）。
- (void)canvas:(PXEditorCanvas *)canvas didRequestTextInputAtViewPoint:(CGPoint)viewPoint;
@end

/// 编辑画布：预览源图 + 标注绘制 + 手势采集。
/// 绘制路径与 PXEditorRenderer 导出路径一致，保证所见即所得。
@interface PXEditorCanvas : UIView

@property (nonatomic, weak, nullable) id<PXEditorCanvasDelegate> delegate;
@property (nonatomic, strong, readonly) PXEditorDocument *document;

@property (nonatomic, assign) PXAnnotationType currentTool;
@property (nonatomic, strong) UIColor *currentColor;
@property (nonatomic, assign) CGFloat currentLineWidth;

- (instancetype)initWithFrame:(CGRect)frame document:(PXEditorDocument *)document;

- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)undo;
- (void)redo;

/// 文字输入完成后放置标注（视图坐标）。
- (void)addTextAnnotationWithText:(NSString *)text atViewPoint:(CGPoint)viewPoint;

- (void)prepareForDismissal;

@end

NS_ASSUME_NONNULL_END
