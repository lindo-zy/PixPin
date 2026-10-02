#import "PXSelectionToolbar.h"

@interface PXSelectionToolbar ()
@property (nonatomic, copy, readwrite) NSArray<UIButton *> *buttons;
@property (nonatomic, assign, readwrite) CGFloat preferredHeight;
@property (nonatomic, assign) CGFloat buttonScale;
@end

@implementation PXSelectionToolbar

- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(PXSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize {
    if ((self = [super initWithFrame:CGRectZero])) {
        iconPointSize = MAX(10.0, MIN(20.0, iconPointSize));
        _buttonScale = iconPointSize / 17.0;
        BOOL stacked = style == PXSelectionButtonStyleIconAndText;
        _preferredHeight = (stacked ? 62.0 : 46.0) * _buttonScale;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
        self.layer.cornerRadius = 14.0 * _buttonScale;
        self.clipsToBounds = YES;

        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        NSMutableArray<UIView *> *stackViews = [NSMutableArray array];
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
            // 窄屏或较长自定义名称不能把等宽按钮撑出工具栏。
            [button setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                   forAxis:UILayoutConstraintAxisHorizontal];
            [buttons addObject:button];
            if (stackViews.count > 0) {
                UIView *separator = [[UIView alloc] init];
                separator.translatesAutoresizingMaskIntoConstraints = NO;
                separator.userInteractionEnabled = NO;
                UIView *line = [[UIView alloc] init];
                line.backgroundColor = UIColor.whiteColor;
                line.translatesAutoresizingMaskIntoConstraints = NO;
                line.userInteractionEnabled = NO;
                [separator addSubview:line];
                [NSLayoutConstraint activateConstraints:@[
                    [separator.widthAnchor constraintEqualToConstant:_buttonScale],
                    [line.topAnchor constraintEqualToAnchor:separator.topAnchor constant:10.0 * _buttonScale],
                    [line.bottomAnchor constraintEqualToAnchor:separator.bottomAnchor constant:-10.0 * _buttonScale],
                    [line.centerXAnchor constraintEqualToAnchor:separator.centerXAnchor],
                    [line.widthAnchor constraintEqualToConstant:_buttonScale],
                ]];
                [stackViews addObject:separator];
            }
            [stackViews addObject:button];
        }
        _buttons = [buttons copy];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:stackViews];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFill;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:2.0 * _buttonScale],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2.0 * _buttonScale],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0 * _buttonScale],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0 * _buttonScale],
        ]];
        for (NSUInteger idx = 1; idx < buttons.count; idx++) {
            [constraints addObject:[buttons[idx].widthAnchor constraintEqualToAnchor:buttons[0].widthAnchor]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
    }
    return self;
}

- (CGFloat)preferredWidthForAvailableWidth:(CGFloat)availableWidth {
    availableWidth = MAX(0.0, availableWidth);
    return MIN(availableWidth, MIN(availableWidth, self.buttons.count * 60.0 + 12.0) * self.buttonScale);
}

@end
