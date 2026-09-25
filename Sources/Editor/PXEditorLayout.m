#import "PXEditorLayout.h"
#import <math.h>

PXEditorGridLayout PXEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns) {
    CGFloat available = MAX(0.0, width - 20.0);
    NSUInteger columns = MAX(1, MIN(MAX(1, maximumColumns), (NSUInteger)MAX(1.0, floor((available + 6.0) / 50.0))));
    NSUInteger rows = (count + columns - 1) / columns;
    CGFloat buttonWidth = MAX(0.0, floor((available - 6.0 * (columns - 1)) / columns));
    return (PXEditorGridLayout){ columns, rows, buttonWidth, rows ? rows * 44.0 + (rows - 1) * 8.0 : 0.0 };
}

CGRect PXEditorGridFrame(PXEditorGridLayout layout, NSUInteger index) {
    return CGRectMake(10.0 + (index % layout.columns) * (layout.buttonWidth + 6.0),
                      (index / layout.columns) * 52.0, layout.buttonWidth, 44.0);
}
