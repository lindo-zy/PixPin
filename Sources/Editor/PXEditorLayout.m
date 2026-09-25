#import "PXEditorLayout.h"
#import <math.h>

PXEditorGridLayout PXEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns) {
    CGFloat available = MAX(0.0, width - 16.0);
    NSUInteger columns = MAX(1, MIN(MAX(1, maximumColumns), (NSUInteger)MAX(1.0, floor((available + 4.0) / 42.0))));
    NSUInteger rows = (count + columns - 1) / columns;
    CGFloat buttonWidth = MAX(0.0, floor((available - 4.0 * (columns - 1)) / columns));
    return (PXEditorGridLayout){ columns, rows, buttonWidth, rows ? rows * 38.0 + (rows - 1) * 4.0 : 0.0 };
}

CGRect PXEditorGridFrame(PXEditorGridLayout layout, NSUInteger index) {
    return CGRectMake(8.0 + (index % layout.columns) * (layout.buttonWidth + 4.0),
                      (index / layout.columns) * 42.0, layout.buttonWidth, 38.0);
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
