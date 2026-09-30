#import "PXEditorLayout.h"
#import <math.h>

PXEditorGridLayout PXEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns) {
    CGFloat available = MAX(0.0, width - 16.0);
    NSUInteger columns = MAX(1, MIN(MAX(1, maximumColumns), (NSUInteger)MAX(1.0, floor((available + 4.0) / 42.0))));
    NSUInteger rows = (count + columns - 1) / columns;
    CGFloat buttonWidth = MAX(0.0, floor((available - 4.0 * (columns - 1)) / columns));
    return (PXEditorGridLayout){ columns, rows, buttonWidth,
        rows ? rows * 38.0 + (rows - 1) * 4.0 : 0.0, 38.0, 4.0, 8.0 };
}

PXEditorGridLayout PXEditorGridMakeScaled(CGFloat width, NSUInteger count, NSUInteger maximumColumns, CGFloat scale) {
    if (!isfinite(scale) || scale <= 0) scale = 1.0;
    // 放大时减少列数以避免溢出；缩小时沿用基准列数，避免均分宽度把按钮重新撑大。
    PXEditorGridLayout layout = PXEditorGridMake(width / MAX(1.0, scale), count, maximumColumns);
    if (scale == 1.0) return layout;
    layout.buttonWidth *= scale;
    layout.buttonHeight *= scale;
    layout.gap *= scale;
    layout.height *= scale;
    CGFloat gridWidth = layout.columns * layout.buttonWidth + (layout.columns - 1) * layout.gap;
    layout.originX = MAX(0.0, (width - gridWidth) / 2.0);
    return layout;
}

CGRect PXEditorGridFrame(PXEditorGridLayout layout, NSUInteger index) {
    return CGRectMake(layout.originX + (index % layout.columns) * (layout.buttonWidth + layout.gap),
                      (index / layout.columns) * (layout.buttonHeight + layout.gap),
                      layout.buttonWidth, layout.buttonHeight);
}

CGRect PXEditorMarkupImageViewport(CGSize size, CGRect panel,
                                   CGFloat safeTop, CGFloat safeLeft,
                                   CGFloat safeBottom, CGFloat safeRight,
                                   CGFloat sliderSpace, BOOL panelAtTop) {
    CGFloat top = panelAtTop ? CGRectGetMaxY(panel) + 8.0 : safeTop;
    CGFloat bottom = panelAtTop ? size.height - safeBottom : CGRectGetMinY(panel) - sliderSpace - 8.0;
    return CGRectMake(safeLeft, top, MAX(1.0, size.width - safeLeft - safeRight), MAX(1.0, bottom - top));
}

CGPoint PXEditorClampFloatingOrigin(CGPoint origin, CGSize floatingSize, CGRect allowedBounds) {
    CGFloat maxX = MAX(CGRectGetMinX(allowedBounds), CGRectGetMaxX(allowedBounds) - floatingSize.width);
    CGFloat maxY = MAX(CGRectGetMinY(allowedBounds), CGRectGetMaxY(allowedBounds) - floatingSize.height);
    return CGPointMake(MAX(CGRectGetMinX(allowedBounds), MIN(origin.x, maxX)),
                       MAX(CGRectGetMinY(allowedBounds), MIN(origin.y, maxY)));
}
