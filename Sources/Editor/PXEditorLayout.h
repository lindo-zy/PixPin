#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// 与 UIKit 无关：按 44pt 最小触控宽度换行，统一供操作、工具和贴纸网格使用。
typedef struct {
    NSUInteger columns;
    NSUInteger rows;
    CGFloat buttonWidth;
    CGFloat height;
} PXEditorGridLayout;

PXEditorGridLayout PXEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns);
CGRect PXEditorGridFrame(PXEditorGridLayout layout, NSUInteger index);
