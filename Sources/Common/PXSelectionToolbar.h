#import <UIKit/UIKit.h>
#import "PXEditorOrder.h"

NS_ASSUME_NONNULL_BEGIN

/// 选区与设置预览共用的工具栏；外观在创建时取快照，调用方负责按钮动作。
@interface PXSelectionToolbar : UIView
@property (nonatomic, copy, readonly) NSArray<UIButton *> *buttons;
@property (nonatomic, assign, readonly) CGFloat preferredHeight;
- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(PXSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize;
- (CGFloat)preferredWidthForAvailableWidth:(CGFloat)availableWidth;
@end

NS_ASSUME_NONNULL_END
