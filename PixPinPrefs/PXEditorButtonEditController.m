#import "PXEditorButtonEditController.h"

static const CGFloat PXIconItemSide = 52.0;

@interface PXEditorButtonEditController () <UITextFieldDelegate, UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) BOOL isAction;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *defaultIconName;
@property (nonatomic, copy) NSString *customName;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UICollectionView *iconGrid;
// 选中的符号名；NSNull = 使用默认图标（与 customIcon 为空同义）。
@property (nonatomic, strong) id selectedIcon;
@property (nonatomic, copy) NSArray<NSString *> *symbols;
@property (nonatomic, copy) void (^onSave)(NSString *name, NSString *iconName);
@end

@implementation PXEditorButtonEditController

- (instancetype)initWithIdentifier:(NSString *)identifier
                        isAction:(BOOL)isAction
                        displayName:(NSString *)displayName
                  defaultIconName:(NSString *)defaultIconName
                       customName:(NSString *)customName
                   customIconName:(NSString *)customIconName
                           onSave:(void (^)(NSString * _Nullable, NSString * _Nullable))onSave {
    if (self = [super init]) {
        _identifier = identifier;
        _isAction = isAction;
        _displayName = displayName;
        _defaultIconName = defaultIconName;
        _customName = customName;
        _onSave = onSave;
        _selectedIcon = customIconName.length > 0 ? customIconName : NSNull.null;
        _symbols = [self pxAvailableSymbols];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.title = self.displayName;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(pxCancelTapped:)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(pxSaveTapped:)];

    UILabel *nameCaption = [[UILabel alloc] init];
    nameCaption.text = @"显示名称（留空恢复默认）";
    nameCaption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    nameCaption.textColor = [UIColor secondaryLabelColor];
    nameCaption.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:nameCaption];

    _nameField = [[UITextField alloc] init];
    _nameField.borderStyle = UITextBorderStyleRoundedRect;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.delegate = self;
    // 占位提示目录默认名；已有自定义名必须回填，否则直接点保存会静默清除覆盖。
    _nameField.placeholder = self.displayName;
    _nameField.text = self.customName ?: @"";
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_nameField];

    UILabel *iconCaption = [[UILabel alloc] init];
    iconCaption.text = @"图标";
    iconCaption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    iconCaption.textColor = [UIColor secondaryLabelColor];
    iconCaption.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:iconCaption];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(PXIconItemSide, PXIconItemSide);
    layout.minimumInteritemSpacing = 8.0;
    layout.minimumLineSpacing = 8.0;
    _iconGrid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _iconGrid.backgroundColor = UIColor.clearColor;
    _iconGrid.dataSource = self;
    _iconGrid.delegate = self;
    [_iconGrid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"icon"];
    _iconGrid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_iconGrid];

    [NSLayoutConstraint activateConstraints:@[
        [nameCaption.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [nameCaption.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [nameCaption.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_nameField.topAnchor constraintEqualToAnchor:nameCaption.bottomAnchor constant:6],
        [_nameField.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [_nameField.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_nameField.heightAnchor constraintEqualToConstant:38],
        [iconCaption.topAnchor constraintEqualToAnchor:_nameField.bottomAnchor constant:16],
        [iconCaption.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [iconCaption.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_iconGrid.topAnchor constraintEqualToAnchor:iconCaption.bottomAnchor constant:6],
        [_iconGrid.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [_iconGrid.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_iconGrid.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
}

#pragma mark - 符号清单

/// 精选符号（目录默认图标之外的可选集）；运行时过滤当前系统加载不到的符号。
- (NSArray<NSString *> *)pxAvailableSymbols {
    NSArray<NSString *> *candidates = @[
        @"star", @"heart", @"flag", @"scissors", @"wand.and.stars", @"eyedropper",
        @"highlighter", @"signature", @"square.and.pencil", @"ruler", @"eraser", @"paintpalette",
        @"face.smiling", @"hand.raised", @"hand.tap", @"link", @"paperplane", @"bookmark",
        @"tag", @"bell", @"bolt", @"wifi", @"camera", @"photo",
        @"square.grid.2x2", @"number", @"textformat.size", @"clock", @"calendar", @"location",
        @"trash", @"arrow.clockwise", @"arrow.up.to.line", @"square.and.arrow.up", @"square.and.arrow.down",
        @"pencil", @"paintbrush", @"rectangle", @"ellipse", @"line.diagonal", @"circle.lefthalf.filled",
    ];
    NSMutableArray<NSString *> *available = [NSMutableArray array];
    for (NSString *symbol in candidates) {
        if ([UIImage systemImageNamed:symbol]) [available addObject:symbol];
    }
    return available;
}

#pragma mark - 名称输入

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - 图标网格

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    // 首项固定为"默认"。
    return self.symbols.count + 1;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"icon"
                                                                           forIndexPath:indexPath];
    // 复用清理：移除旧内容后重建（格子内容简单，重建成本低）。
    for (UIView *subview in cell.contentView.subviews) [subview removeFromSuperview];
    cell.contentView.layer.cornerRadius = 10.0;
    cell.contentView.layer.borderWidth = 1.0;

    BOOL isDefaultItem = indexPath.item == 0;
    NSString *symbol = isDefaultItem ? nil : self.symbols[indexPath.item - 1];
    id current = self.selectedIcon;
    BOOL selected = isDefaultItem ? (current == NSNull.null || current == nil)
                                  : ([current isKindOfClass:[NSString class]] && [current isEqualToString:symbol]);
    cell.contentView.backgroundColor = selected ? [UIColor systemBlueColor] : [UIColor secondarySystemGroupedBackgroundColor];
    cell.contentView.layer.borderColor = selected ? [UIColor systemBlueColor].CGColor : [UIColor separatorColor].CGColor;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:isDefaultItem
        ? (self.defaultIconName ?: @"questionmark") : symbol]];
    iconView.tintColor = selected ? UIColor.whiteColor : [UIColor systemBlueColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.isAccessibilityElement = YES;
    iconView.accessibilityLabel = isDefaultItem ? @"默认图标" : symbol;
    [cell.contentView addSubview:iconView];
    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:26],
        [iconView.heightAnchor constraintEqualToConstant:26],
    ]];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    [self.nameField resignFirstResponder];
    self.selectedIcon = indexPath.item == 0 ? NSNull.null : self.symbols[indexPath.item - 1];
    [self.iconGrid reloadData];
}

#pragma mark - 保存/取消

- (void)pxSaveTapped:(UIBarButtonItem *)sender {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *icon = [self.selectedIcon isKindOfClass:[NSString class]] ? self.selectedIcon : nil;
    if (self.onSave) self.onSave(name.length > 0 ? name : nil, icon);
}

- (void)pxCancelTapped:(UIBarButtonItem *)sender {
    // 纯展示层：未保存的输入直接丢弃。
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
