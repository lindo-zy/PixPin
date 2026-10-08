#import "PXEditorLayout.h"
#import <math.h>

const CGFloat PXEditorPanelPadTop = 10.0;
const CGFloat PXEditorPanelPadBottom = 12.0;
const CGFloat PXEditorPanelSideMargin = 52.0;
const CGFloat PXEditorPanelGripHeight = 24.0;

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

PXEditorMarkupGridLayout PXEditorMarkupGridMakeScaled(CGFloat width, NSUInteger count,
                                                     CGFloat sideMargin, CGFloat scale) {
    PXEditorGridLayout grid = PXEditorGridMakeScaled(width - 2.0 * sideMargin, count, 8, scale);
    PXEditorGridLayout fullWidthGrid = PXEditorGridMakeScaled(width, count, 8, scale);
    NSUInteger edgeColumns = MIN(grid.columns, 6);
    NSUInteger middleColumns = fullWidthGrid.columns;
    NSUInteger rows = 0;
    if (count > 0) {
        rows = count <= edgeColumns ? 1 : 2;
        if (count > 2 * edgeColumns) {
            rows += (count - 2 * edgeColumns + middleColumns - 1) / middleColumns;
        }
    }
    // 四角键是 buttonWidth 大小的正方形；宽面板上也要与中间排侧边按钮保持间隔。
    CGFloat stride = MAX(grid.buttonHeight + grid.gap,
                         (grid.buttonWidth + grid.buttonHeight) / 2.0 + grid.gap);
    grid.rows = rows;
    grid.height = rows ? grid.buttonHeight + (rows - 1) * stride : 0.0;
    return (PXEditorMarkupGridLayout){ grid, count, edgeColumns, middleColumns, width,
        MIN(grid.buttonWidth, fullWidthGrid.buttonWidth), stride };
}

CGRect PXEditorMarkupGridFrame(PXEditorMarkupGridLayout layout, NSUInteger index) {
    if (index >= layout.itemCount) return CGRectZero;
    PXEditorGridLayout grid = layout.grid;
    NSUInteger row = 0, column = index;
    BOOL middle = NO;
    if (index >= layout.edgeColumns) {
        NSUInteger remainingIndex = index - layout.edgeColumns;
        NSUInteger middleColumns = layout.middleColumns;
        // 给末排至少保留一个按钮，避免数量刚超过两排容量时出现空末排。
        NSUInteger middleCount = grid.rows > 2
            ? MIN((grid.rows - 2) * middleColumns, layout.itemCount - layout.edgeColumns - 1) : 0;
        middle = remainingIndex < middleCount;
        row = middle ? 1 + remainingIndex / middleColumns : grid.rows - 1;
        column = middle ? remainingIndex % middleColumns : remainingIndex - middleCount;
    }
    NSUInteger columns = middle ? layout.middleColumns : layout.edgeColumns;
    CGFloat buttonWidth = middle ? layout.middleButtonWidth : grid.buttonWidth;
    CGFloat rowWidth = columns * buttonWidth + (columns - 1) * grid.gap;
    CGFloat x = (layout.panelWidth - rowWidth) / 2.0 + column * (buttonWidth + grid.gap);
    return CGRectMake(x, row * layout.rowStride, buttonWidth, grid.buttonHeight);
}

PXEditorMarkupCornerFrames PXEditorMarkupCornerFramesMake(PXEditorGridLayout layout,
                                                          CGFloat panelWidth, CGFloat gridY,
                                                          CGFloat visibleHeight) {
    CGFloat keySize = layout.buttonWidth;
    CGFloat band = (PXEditorPanelSideMargin + layout.originX) / 2.0;
    CGFloat topY = gridY + layout.buttonHeight / 2.0 - keySize / 2.0;
    CGFloat bottomY = gridY + MIN(layout.height, visibleHeight) - layout.buttonHeight / 2.0 - keySize / 2.0;
    CGFloat leftX = band - keySize / 2.0;
    CGFloat rightX = panelWidth - band - keySize / 2.0;
    return (PXEditorMarkupCornerFrames){
        CGRectMake(leftX, topY, keySize, keySize), CGRectMake(rightX, topY, keySize, keySize),
        CGRectMake(leftX, bottomY, keySize, keySize), CGRectMake(rightX, bottomY, keySize, keySize)
    };
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
