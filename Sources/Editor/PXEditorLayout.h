#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// 与 UIKit 无关：紧凑多排网格，统一供操作、工具和贴纸使用。
typedef struct {
    NSUInteger columns;
    NSUInteger rows;
    CGFloat buttonWidth;
    CGFloat height;
    CGFloat buttonHeight;
    CGFloat gap;
    CGFloat originX;
} PXEditorGridLayout;

PXEditorGridLayout PXEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns);
// 17pt 图标对应 scale=1；按钮宽高和间距同比缩放，整组在可用宽度内居中。
PXEditorGridLayout PXEditorGridMakeScaled(CGFloat width, NSUInteger count, NSUInteger maximumColumns, CGFloat scale);
CGRect PXEditorGridFrame(PXEditorGridLayout layout, NSUInteger index);

// 全屏标记：首尾排避开四角，中间排使用两侧空位，最多 8 列。
// grid 保留原窄网格的按钮尺寸和 originX，供四角键沿用原定位。
typedef struct {
    PXEditorGridLayout grid;
    NSUInteger itemCount;
    NSUInteger edgeColumns;
    NSUInteger middleColumns;
    CGFloat panelWidth;
    CGFloat middleButtonWidth;
    CGFloat rowStride;
} PXEditorMarkupGridLayout;

PXEditorMarkupGridLayout PXEditorMarkupGridMakeScaled(CGFloat width, NSUInteger count,
                                                     CGFloat sideMargin, CGFloat scale);
CGRect PXEditorMarkupGridFrame(PXEditorMarkupGridLayout layout, NSUInteger index);

// 实际面板与设置预览共用的内边距、把手高度和四角定位。
FOUNDATION_EXPORT const CGFloat PXEditorPanelPadTop;
FOUNDATION_EXPORT const CGFloat PXEditorPanelPadBottom;
FOUNDATION_EXPORT const CGFloat PXEditorPanelSideMargin;
FOUNDATION_EXPORT const CGFloat PXEditorPanelGripHeight;
FOUNDATION_EXPORT const CGFloat PXEditorRowSliderHeight;
FOUNDATION_EXPORT const CGFloat PXEditorPanelRowGap;

typedef struct {
    CGRect close;
    CGRect color;
    CGRect undo;
    CGRect done;
} PXEditorMarkupCornerFrames;

PXEditorMarkupCornerFrames PXEditorMarkupCornerFramesMake(PXEditorGridLayout layout,
                                                          CGFloat panelWidth, CGFloat gridY,
                                                          CGFloat visibleHeight);

// 全屏标记在独立线宽条和浮动面板之外显示完整图片。
CGRect PXEditorMarkupImageViewport(CGSize size, CGRect panel,
                                   CGFloat safeTop, CGFloat safeLeft,
                                   CGFloat safeBottom, CGFloat safeRight,
                                   CGFloat sliderSpace, BOOL panelAtTop);

// 将浮动面板（或折叠把手）完整限制在可用矩形内。
CGPoint PXEditorClampFloatingOrigin(CGPoint origin, CGSize floatingSize, CGRect allowedBounds);
