#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// 与 UIKit 无关：紧凑多排网格，统一供操作、工具和贴纸使用。
typedef struct {
    NSUInteger columns;
    NSUInteger rows;
    CGFloat buttonWidth;
    CGFloat height;
} PXEditorGridLayout;

PXEditorGridLayout PXEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns);
CGRect PXEditorGridFrame(PXEditorGridLayout layout, NSUInteger index);

// 全屏标记在独立线宽条和浮动面板之外显示完整图片。
CGRect PXEditorMarkupImageViewport(CGSize size, CGRect panel,
                                   CGFloat safeTop, CGFloat safeLeft,
                                   CGFloat safeBottom, CGFloat safeRight,
                                   CGFloat sliderSpace, BOOL panelAtTop);
