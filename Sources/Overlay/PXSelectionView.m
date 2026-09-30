#import "PXSelectionView.h"
#import "../Common/PXEditorOrder.h"

static const CGFloat PXSelectionMinimumSize = 44.0;   // 点；过小选区会产出无意义的细条裁剪
static const CGFloat PXHandleHitRadius = 36.0;

typedef NS_ENUM(NSInteger, PXSelectionDragMode) {
    PXSelectionDragModeNone = 0,
    PXSelectionDragModeMove = 1,
    PXSelectionDragModeCreate = 2,
    PXSelectionDragModeHandle = 3,
};

@interface PXSelectionView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) CAShapeLayer *dimLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) NSMutableArray<UIView *> *handles;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;

@property (nonatomic, assign) CGRect selectionRect;
@property (nonatomic, assign) PXSelectionDragMode dragMode;
@property (nonatomic, assign) NSInteger activeHandleIndex;
@property (nonatomic, assign) CGPoint dragAnchor;
@property (nonatomic, assign) CGRect dragStartRect;
@property (nonatomic, assign) BOOL isInstantMode;
@property (nonatomic, assign) PXCaptureMode mode;
@property (nonatomic, assign) CGFloat buttonScale;
@end

@implementation PXSelectionView

- (instancetype)initWithFrame:(CGRect)frame
                    baseImage:(UIImage *)baseImage
                         mode:(PXCaptureMode)mode
                     delegate:(id<PXSelectionViewDelegate>)delegate {
    if (self = [super initWithFrame:frame]) {
        _delegate = delegate;
        _mode = mode;
        _isInstantMode = (mode == PXCaptureModeInstant);
        _dragMode = PXSelectionDragModeNone;
        [self pxBuildContentWithBaseImage:baseImage];
        [self pxResetSelectionToDefault];
        [self pxUpdateVisuals];
    }
    return self;
}

- (void)dealloc {
    [self prepareForDismissal];
}

#pragma mark - 构建

- (void)pxBuildContentWithBaseImage:(UIImage *)baseImage {
    self.backgroundColor = [UIColor blackColor];

    _backgroundImageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _backgroundImageView.image = baseImage;
    _backgroundImageView.contentMode = UIViewContentModeScaleToFill;   // 归一化图与屏幕同比例
    _backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_backgroundImageView];

    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    _dimLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
    [self.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = [UIColor clearColor].CGColor;
    _borderLayer.strokeColor = [UIColor whiteColor].CGColor;
    _borderLayer.lineWidth = 1.5;
    [self.layer addSublayer:_borderLayer];

    _handles = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < 8; i++) {
        UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 14)];
        handle.backgroundColor = [UIColor whiteColor];
        handle.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
        handle.layer.borderWidth = 1.0;
        handle.layer.cornerRadius = 7.0;
        handle.userInteractionEnabled = NO;
        [self addSubview:handle];
        [_handles addObject:handle];
    }

    _sizeLabel = [[UILabel alloc] init];
    _sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _sizeLabel.textColor = [UIColor whiteColor];
    _sizeLabel.textAlignment = NSTextAlignmentCenter;
    _sizeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    _sizeLabel.layer.cornerRadius = 6.0;
    _sizeLabel.clipsToBounds = YES;
    [self addSubview:_sizeLabel];

    _modeLabel = [[UILabel alloc] init];
    _modeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _modeLabel.textColor = [UIColor whiteColor];
    _modeLabel.textAlignment = NSTextAlignmentCenter;
    _modeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    _modeLabel.layer.cornerRadius = 9.0;
    _modeLabel.clipsToBounds = YES;
    switch (self.mode) {
        case PXCaptureModeFreeze: _modeLabel.text = @"  冻结截图  "; break;
        case PXCaptureModeInstant: _modeLabel.text = @"  即时区域  "; break;
        default: _modeLabel.text = @"  区域截图  "; break;
    }
    [_modeLabel sizeToFit];
    [self addSubview:_modeLabel];

    _toolbar = [[UIView alloc] init];
    _toolbar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    _toolbar.layer.cornerRadius = 14.0;
    _toolbar.clipsToBounds = YES;
    [self addSubview:_toolbar];

    _buttons = [[NSMutableArray alloc] init];
    // 按钮目录化：顺序与显隐来自设置页（PXEditorOrder），即时模式过滤为快速三键。
    NSArray<NSString *> *order = [PXEditorOrder visibleSelectionOrderForOrder:[PXEditorOrder currentSelectionOrder]
                                                                      hidden:[PXEditorOrder currentSelectionHidden]
                                                                     instant:_isInstantMode];
    // 显示样式跟随设置页：图标加载失败自动回退文字，名称与图标均吃自定义覆盖。
    BOOL showIcon = [PXEditorOrder selectionShowsIcon];
    CGFloat iconPointSize = [PXEditorOrder buttonIconPointSize];
    self.buttonScale = showIcon ? iconPointSize / 17.0 : 1.0;
    _toolbar.layer.cornerRadius = 14.0 * self.buttonScale;
    NSMutableArray<UIView *> *stackViews = [[NSMutableArray alloc] init];
    for (NSString *identifier in order) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tintColor = [UIColor whiteColor];
        NSString *name = [PXEditorOrder displayNameForSelectionIdentifier:identifier];
        button.accessibilityLabel = name;
        UIImage *icon = nil;
        if (showIcon) {
            NSString *symbol = [PXEditorOrder iconNameForSelectionIdentifier:identifier];
            icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
            if (icon) {
                icon = [icon imageWithConfiguration:
                    [UIImageSymbolConfiguration configurationWithPointSize:iconPointSize
                                                                    weight:UIImageSymbolWeightMedium]];
            }
        }
        if (icon) {
            [button setImage:icon forState:UIControlStateNormal];
        } else {
            [button setTitle:name forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:15 * self.buttonScale weight:UIFontWeightSemibold];
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
        }
        [button addTarget:self action:@selector(pxButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.accessibilityIdentifier = identifier;
        [_buttons addObject:button];
        [stackViews addObject:button];
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:stackViews];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_toolbar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:_toolbar.topAnchor constant:2 * self.buttonScale],
        [stack.bottomAnchor constraintEqualToAnchor:_toolbar.bottomAnchor constant:-2 * self.buttonScale],
        [stack.leadingAnchor constraintEqualToAnchor:_toolbar.leadingAnchor constant:6 * self.buttonScale],
        [stack.trailingAnchor constraintEqualToAnchor:_toolbar.trailingAnchor constant:-6 * self.buttonScale],
    ]];

    _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pxHandlePan:)];
    _panGesture.delegate = self;
    [self addGestureRecognizer:_panGesture];
}

#pragma mark - 选区几何

- (void)applyDefaultSelectionRect:(CGRect)rect {
    self.selectionRect = rect;
    [self pxUpdateVisuals];
}

- (void)pxResetSelectionToDefault {
    CGRect bounds = self.bounds;
    // 区域模式默认居中 70%，保证一进来就有可用的初始选区。
    CGRect rect = CGRectMake(bounds.size.width * 0.15, bounds.size.height * 0.18,
                             bounds.size.width * 0.7, bounds.size.height * 0.64);
    self.selectionRect = PXClampSelectionRect(rect, bounds.size, PXSelectionMinimumSize);
}

- (void)pxSetSelectionRect:(CGRect)rect {
    CGRect clamped = PXClampSelectionRect(rect, self.bounds.size, PXSelectionMinimumSize);
    if (CGRectEqualToRect(clamped, CGRectZero)) {
        return;   // 太小的中间态直接忽略，保持上一个合法选区
    }
    self.selectionRect = clamped;
    [self pxUpdateVisuals];
}

- (void)pxUpdateVisuals {
    CGRect selection = self.selectionRect;

    UIBezierPath *full = [UIBezierPath bezierPathWithRect:self.bounds];
    [full appendPath:[UIBezierPath bezierPathWithRect:selection]];
    _dimLayer.path = full.CGPath;

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:selection];
    _borderLayer.path = border.CGPath;

    // 角 0-3：左上/右上/右下/左下；边 4-7：上/右/下/左
    CGFloat w = selection.size.width, h = selection.size.height;
    CGFloat x = selection.origin.x, y = selection.origin.y;
    CGPoint centers[8] = {
        CGPointMake(x, y), CGPointMake(x + w, y), CGPointMake(x + w, y + h), CGPointMake(x, y + h),
        CGPointMake(x + w / 2, y), CGPointMake(x + w, y + h / 2), CGPointMake(x + w / 2, y + h), CGPointMake(x, y + h / 2),
    };
    for (NSInteger i = 0; i < 8; i++) {
        UIView *handle = self.handles[i];
        handle.center = centers[i];
        handle.hidden = CGRectIsEmpty(selection);
    }

    CGFloat pixelW = selection.size.width * [UIScreen mainScreen].scale;
    CGFloat pixelH = selection.size.height * [UIScreen mainScreen].scale;
    _sizeLabel.text = [NSString stringWithFormat:@"%.0f × %.0f px", pixelW, pixelH];
    [_sizeLabel sizeToFit];
    CGRect labelFrame = _sizeLabel.frame;
    labelFrame.origin.x = selection.origin.x + selection.size.width / 2 - labelFrame.size.width / 2 - 8;
    labelFrame.origin.y = selection.origin.y + selection.size.height + 10;
    if (labelFrame.origin.y + labelFrame.size.height > self.bounds.size.height - 70) {
        labelFrame.origin.y = selection.origin.y - labelFrame.size.height - 10;
    }
    labelFrame.size.width += 16;
    labelFrame.size.height = fmax(labelFrame.size.height, 20);
    _sizeLabel.frame = CGRectIntegral(labelFrame);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat safeBottom = self.safeAreaInsets.bottom;
    CGFloat availableWidth = MAX(0.0, self.bounds.size.width - 24.0);
    CGFloat toolbarWidth = MIN(availableWidth,
        MIN(availableWidth, self.buttons.count * 60.0 + 12.0) * self.buttonScale);
    CGFloat toolbarHeight = 46.0 * self.buttonScale;
    _toolbar.frame = CGRectMake((self.bounds.size.width - toolbarWidth) / 2.0,
                                self.bounds.size.height - safeBottom - 12.0 - toolbarHeight,
                                toolbarWidth, toolbarHeight);
    CGSize modeTextSize = [_modeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 28.0)];
    CGFloat modeLabelWidth = modeTextSize.width + 16.0;
    _modeLabel.frame = CGRectMake((self.bounds.size.width - modeLabelWidth) / 2.0,
                                  self.safeAreaInsets.top + 10.0,
                                  modeLabelWidth,
                                  28.0);

    if (!CGRectIsEmpty(self.selectionRect)) {
        CGRect clamped = PXClampSelectionRect(self.selectionRect, self.bounds.size, PXSelectionMinimumSize);
        if (!CGRectEqualToRect(clamped, CGRectZero) && !CGRectEqualToRect(clamped, self.selectionRect)) {
            self.selectionRect = clamped;
        }
    }
    [self pxUpdateVisuals];
    [self bringSubviewToFront:self.modeLabel];
    [self bringSubviewToFront:self.toolbar];
}

#pragma mark - 手势

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 操作栏按钮必须独占触摸，否则轻微手指移动会被选区 pan 取消。
    return ![touch.view isDescendantOfView:self.toolbar];
}

- (void)pxHandlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    CGPoint translation = [gesture translationInView:self];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            _dragStartRect = self.selectionRect;
            _dragAnchor = location;
            NSInteger handleIndex = [self pxHandleIndexAtPoint:location];
            if (handleIndex >= 0) {
                _dragMode = PXSelectionDragModeHandle;
                _activeHandleIndex = handleIndex;
            } else if (CGRectContainsPoint(self.selectionRect, location)) {
                _dragMode = PXSelectionDragModeMove;
            } else {
                _dragMode = PXSelectionDragModeCreate;
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            switch (_dragMode) {
                case PXSelectionDragModeMove: {
                    CGRect rect = _dragStartRect;
                    rect.origin.x += translation.x;
                    rect.origin.y += translation.y;
                    [self pxSetSelectionRect:rect];
                    break;
                }
                case PXSelectionDragModeCreate: {
                    CGRect rect = CGRectMake(MIN(_dragAnchor.x, location.x),
                                             MIN(_dragAnchor.y, location.y),
                                             fabs(location.x - _dragAnchor.x),
                                             fabs(location.y - _dragAnchor.y));
                    [self pxSetSelectionRect:rect];
                    break;
                }
                case PXSelectionDragModeHandle: {
                    [self pxResizeWithHandle:_activeHandleIndex location:location];
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (_dragMode != PXSelectionDragModeNone) {
                CGRect clamped = PXClampSelectionRect(self.selectionRect, self.bounds.size, PXSelectionMinimumSize);
                if (CGRectEqualToRect(clamped, CGRectZero)) {
                    [self pxResetSelectionToDefault];
                } else {
                    self.selectionRect = clamped;
                }
                [self pxUpdateVisuals];
            }
            _dragMode = PXSelectionDragModeNone;
            break;
        }
        default:
            break;
    }
}

- (NSInteger)pxHandleIndexAtPoint:(CGPoint)point {
    NSInteger best = -1;
    CGFloat bestDistance = PXHandleHitRadius;
    for (NSInteger i = 0; i < 8; i++) {
        CGFloat distance = hypot(self.handles[i].center.x - point.x, self.handles[i].center.y - point.y);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

- (void)pxResizeWithHandle:(NSInteger)index location:(CGPoint)location {
    CGRect rect = _dragStartRect;
    CGFloat minX = MIN(rect.origin.x, rect.origin.x + rect.size.width);
    CGFloat maxX = MAX(rect.origin.x, rect.origin.x + rect.size.width);
    CGFloat minY = MIN(rect.origin.y, rect.origin.y + rect.size.height);
    CGFloat maxY = MAX(rect.origin.y, rect.origin.y + rect.size.height);

    switch (index) {
        case 0: minX = location.x; minY = location.y; break;
        case 1: maxX = location.x; minY = location.y; break;
        case 2: maxX = location.x; maxY = location.y; break;
        case 3: minX = location.x; maxY = location.y; break;
        case 4: minY = location.y; break;
        case 5: maxX = location.x; break;
        case 6: maxY = location.y; break;
        case 7: minX = location.x; break;
        default: return;
    }

    CGRect updated = CGRectMake(minX, minY, maxX - minX, maxY - minY);
    if (updated.size.width < PXSelectionMinimumSize || updated.size.height < PXSelectionMinimumSize) {
        return;   // 拖得太小的过程不抖动，松手时统一钳制
    }
    self.selectionRect = updated;
    [self pxUpdateVisuals];
}

#pragma mark - 按钮

- (void)pxButtonTapped:(UIButton *)sender {
    NSString *identifier = sender.accessibilityIdentifier;
    if ([identifier isEqualToString:@"cancel"]) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidCancel:)]) {
            [self.delegate selectionViewDidCancel:self];
        }
        return;
    }
    if ([identifier isEqualToString:@"editor"]) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestEditor:displayRect:)]) {
            [self.delegate selectionViewDidRequestEditor:self displayRect:self.selectionRect];
        }
        return;
    }
    if ([identifier isEqualToString:@"float"]) {
        // 悬浮与确认同样要求合法选区：细条/零矩形没有悬浮价值。
        if (CGRectIsEmpty(PXClampSelectionRect(self.selectionRect, self.bounds.size, PXSelectionMinimumSize))) {
            return;
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(selectionViewDidRequestFloat:displayRect:)]) {
            [self.delegate selectionViewDidRequestFloat:self displayRect:self.selectionRect];
        }
        return;
    }
    if ([identifier isEqualToString:@"selectall"]) {
        [self pxSetSelectionRect:self.bounds];
        return;
    }

    PXOutputAction action = PXOutputActionPreviewOnly;
    if ([identifier isEqualToString:@"save"]) action = PXOutputActionSave;
    else if ([identifier isEqualToString:@"copy"]) action = PXOutputActionCopy;
    else if ([identifier isEqualToString:@"confirm"]) action = PXOutputActionPreviewOnly;

    if (CGRectIsEmpty(PXClampSelectionRect(self.selectionRect, self.bounds.size, PXSelectionMinimumSize))) {
        return;   // 没有合法选区时不触发确认
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(selectionView:didConfirmDisplayRect:action:)]) {
        [self.delegate selectionView:self didConfirmDisplayRect:self.selectionRect action:action];
    }
}

#pragma mark - 清理

- (void)prepareForDismissal {
    if (_panGesture) {
        [self removeGestureRecognizer:_panGesture];
        _panGesture = nil;
    }
    _delegate = nil;
    _dimLayer = nil;
    _borderLayer = nil;
    [_handles removeAllObjects];
    _backgroundImageView.image = nil;
}

@end
