#import "PXSelectionToolbar.h"
#import "PXLog.h"
#import <math.h>

@interface PXSelectionToolbar ()
@property (nonatomic, copy, readwrite) NSArray<UIButton *> *buttons;
@property (nonatomic, copy) NSArray<UIView *> *separators;
@property (nonatomic, assign) CGFloat buttonScale;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) NSUInteger layoutColumns;
@end

@implementation PXSelectionToolbar

- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(PXSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize {
    if ((self = [super initWithFrame:CGRectZero])) {
        iconPointSize = MAX(10.0, MIN(20.0, iconPointSize));
        _buttonScale = iconPointSize / 17.0;
        BOOL stacked = style == PXSelectionButtonStyleIconAndText;
        _rowHeight = (stacked ? 62.0 : 46.0) * _buttonScale;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
        self.layer.cornerRadius = 14.0 * _buttonScale;
        self.clipsToBounds = YES;

        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        NSMutableArray<UIView *> *separators = [NSMutableArray array];
        for (NSString *identifier in identifiers) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tintColor = UIColor.whiteColor;
            NSString *name = [PXEditorOrder displayNameForSelectionIdentifier:identifier];
            button.accessibilityLabel = name;
            button.accessibilityIdentifier = identifier;
            UIImage *icon = nil;
            if (style != PXSelectionButtonStyleText) {
                NSString *symbol = [PXEditorOrder iconNameForSelectionIdentifier:identifier];
                icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
                if (icon) {
                    icon = [icon imageWithConfiguration:[UIImageSymbolConfiguration
                        configurationWithPointSize:iconPointSize weight:UIImageSymbolWeightMedium]];
                }
            }
            if (stacked && icon) {
                UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
                configuration.baseForegroundColor = UIColor.whiteColor;
                configuration.image = icon;
                configuration.imagePlacement = NSDirectionalRectEdgeTop;
                configuration.imagePadding = 4.0 * _buttonScale;
                configuration.attributedTitle = [[NSAttributedString alloc] initWithString:name attributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:11.0 * _buttonScale weight:UIFontWeightSemibold],
                }];
                configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
                configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
                configuration.contentInsets = NSDirectionalEdgeInsetsMake(4.0 * _buttonScale,
                    2.0 * _buttonScale, 4.0 * _buttonScale, 2.0 * _buttonScale);
                button.configuration = configuration;
            } else if (icon) {
                [button setImage:icon forState:UIControlStateNormal];
            } else {
                // 当前系统不支持自定义符号时，保留名称和可点击的完整按钮。
                [button setTitle:name forState:UIControlStateNormal];
                button.titleLabel.font = [UIFont systemFontOfSize:15.0 * _buttonScale weight:UIFontWeightSemibold];
            }
            button.titleLabel.numberOfLines = 1;
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.5;
            [buttons addObject:button];
            [self addSubview:button];
            if (buttons.count > 1) {
                UIView *separator = [[UIView alloc] init];
                separator.backgroundColor = UIColor.whiteColor;
                separator.userInteractionEnabled = NO;
                [self addSubview:separator];
                [separators addObject:separator];
            }
        }
        _buttons = [buttons copy];
        _separators = [separators copy];
    }
    return self;
}

- (CGFloat)preferredWidthForAvailableWidth:(CGFloat)availableWidth {
    availableWidth = MAX(0.0, availableWidth);
    NSUInteger columns = [self pxColumnsForAvailableWidth:availableWidth];
    return columns ? MIN(availableWidth, (columns * 60.0 + 12.0) * self.buttonScale) : 0.0;
}

- (NSUInteger)pxColumnsForAvailableWidth:(CGFloat)availableWidth {
    if (self.buttons.count == 0) return 0;
    CGFloat contentWidth = MAX(0.0, availableWidth - 12.0 * self.buttonScale);
    // 保留至少 40pt 的基准按钮宽度；空间不足时换行，不继续挤压所有按钮。
    NSUInteger fitting = (NSUInteger)MAX(1.0, floor((contentWidth + self.buttonScale) /
                                                   (41.0 * self.buttonScale)));
    return MIN(MIN(8, self.buttons.count), fitting);
}

- (CGFloat)preferredHeightForAvailableWidth:(CGFloat)availableWidth {
    NSUInteger columns = [self pxColumnsForAvailableWidth:availableWidth];
    if (columns == 0) return 0.0;
    NSUInteger rows = (self.buttons.count + columns - 1) / columns;
    return rows * self.rowHeight + (rows - 1) * 4.0 * self.buttonScale;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    NSUInteger columns = [self pxColumnsForAvailableWidth:width];
    if (columns == 0 || width <= 0.0) return;
    CGFloat scale = self.buttonScale;
    CGFloat buttonWidth = MAX(0.0, (width - 12.0 * scale - (columns - 1) * scale) / columns);
    CGFloat buttonHeight = self.rowHeight - 4.0 * scale;
    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        NSUInteger column = i % columns;
        CGFloat x = 6.0 * scale + column * (buttonWidth + scale);
        CGFloat y = 2.0 * scale + (i / columns) * (self.rowHeight + 4.0 * scale);
        self.buttons[i].frame = CGRectMake(x, y, buttonWidth, buttonHeight);
        if (i > 0) {
            UIView *separator = self.separators[i - 1];
            separator.hidden = (column == 0);
            separator.frame = CGRectMake(x - scale, y + 10.0 * scale,
                                         scale, MAX(0.0, buttonHeight - 20.0 * scale));
        }
    }
    if (self.layoutColumns != columns && self.userInteractionEnabled) {
        PXLogInfo(@"selection toolbar layout: buttons=%lu columns=%lu rows=%lu",
                  (unsigned long)self.buttons.count, (unsigned long)columns,
                  (unsigned long)((self.buttons.count + columns - 1) / columns));
    }
    self.layoutColumns = columns;
}

@end
