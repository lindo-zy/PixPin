#import <Preferences/PSViewController.h>
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

// 自定义 URL 按钮管理：设置页增删改任意个 URL scheme 快捷按钮，
// 按钮出现在截图按钮工具栏，点击后取消当前截图并经 SpringBoard openURL 打开。
// 与 PXEditorOrderController 同款自建 UITableView；Preferences 导航页必须继承
// PSViewController，提供 PSLinkCell 所需的 specifier / parentController 与生命周期接口。

@interface PXCustomURLController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@end

@interface PXCustomURLEditController : PSViewController <UITextFieldDelegate>
- (instancetype)initWithButton:(nullable PXCustomSelectionButton *)button
                       onDelete:(nullable void (^)(void))onDelete;
@end

#pragma mark - 列表

@implementation PXCustomURLController {
    UITableView *_tableView;
}

- (void)loadView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    self.view = _tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"自定义 URL 按钮";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(pxAddTapped:)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_tableView reloadData];
    PXLogInfo(@"prefs custom url list shown: %lu buttons",
              (unsigned long)[PXEditorOrder customSelectionButtons].count);
}

- (void)pxAddTapped:(UIBarButtonItem *)sender {
    [self pxEditButton:nil];
}

- (void)pxEditButton:(nullable PXCustomSelectionButton *)button {
    __weak typeof(self) weakSelf = self;
    void (^onDelete)(void) = button ? ^{
        [PXEditorOrder removeCustomSelectionButtonWithID:button.identifier];
        PXLogInfo(@"prefs custom url removed: %@", button.identifier);
        __strong typeof(weakSelf) self = weakSelf;
        [self.tableView reloadData];
    } : nil;
    // 保存动作在编辑页内直接写 PXEditorOrder；返回后 viewWillAppear 统一刷新。
    PXCustomURLEditController *editor = [[PXCustomURLEditController alloc] initWithButton:button
                                                                                  onDelete:onDelete];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - 数据源

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [PXEditorOrder customSelectionButtons].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"PXCustomURLCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    PXCustomSelectionButton *button = [PXEditorOrder customSelectionButtons][indexPath.row];
    cell.textLabel.text = button.name;
    cell.detailTextLabel.text = button.url;
    NSString *symbol = [PXEditorOrder iconNameForSelectionIdentifier:button.identifier];
    UIImage *icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
    cell.imageView.image = icon;
    cell.imageView.tintColor = [UIColor systemBlueColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [self pxEditButton:[PXEditorOrder customSelectionButtons][indexPath.row]];
}

// 让 UITableView 与 UIViewController 的属性访问统一（onDelete 回调里用）。
- (UITableView *)tableView {
    return _tableView;
}

@end

#pragma mark - 编辑

@interface PXCustomURLEditController ()
@property (nonatomic, strong, nullable) PXCustomSelectionButton *button;
@property (nonatomic, copy, nullable) void (^onDelete)(void);
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *iconField;
@property (nonatomic, strong) UIImageView *iconPreview;
@property (nonatomic, strong) UITextField *urlField;
@end

@implementation PXCustomURLEditController

- (instancetype)initWithButton:(PXCustomSelectionButton *)button
                      onDelete:(void (^)(void))onDelete {
    if (self = [super init]) {
        _button = button;
        _onDelete = onDelete;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.title = self.button ? @"编辑按钮" : @"添加按钮";
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(pxCancelTapped:)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(pxSaveTapped:)];

    UILabel *nameCaption = [self pxCaptionLabelWithText:@"显示名称（工具栏按钮文字）"];
    [self.view addSubview:nameCaption];
    _nameField = [self pxTextFieldWithPlaceholder:@"例如：翻译"];
    _nameField.text = self.button.name ?: @"";
    [self.view addSubview:_nameField];

    UILabel *iconCaption = [self pxCaptionLabelWithText:@"SF 图标名称（留空显示文字）"];
    [self.view addSubview:iconCaption];
    _iconField = [self pxTextFieldWithPlaceholder:@"例如：arrow.up.right"];
    _iconField.text = self.button.iconName.length > 0 ? self.button.iconName : @"";
    [_iconField addTarget:self action:@selector(pxIconChanged:)
         forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_iconField];

    _iconPreview = [[UIImageView alloc] init];
    _iconPreview.contentMode = UIViewContentModeScaleAspectFit;
    _iconPreview.tintColor = [UIColor systemBlueColor];
    [self.view addSubview:_iconPreview];

    UILabel *urlCaption = [self pxCaptionLabelWithText:@"URL（必填，点击按钮时打开）"];
    [self.view addSubview:urlCaption];
    _urlField = [self pxTextFieldWithPlaceholder:@"例如：shortcuts://run-shortcut?name=翻译"];
    _urlField.keyboardType = UIKeyboardTypeURL;
    _urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    _urlField.text = self.button.url ?: @"";
    [self.view addSubview:_urlField];

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 260, 44)];
    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [deleteButton setTitle:@"删除此按钮" forState:UIControlStateNormal];
    [deleteButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    deleteButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [deleteButton addTarget:self action:@selector(pxDeleteTapped:) forControlEvents:UIControlEventTouchUpInside];
    deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:deleteButton];

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
        [_iconField.topAnchor constraintEqualToAnchor:iconCaption.bottomAnchor constant:6],
        [_iconField.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [_iconField.trailingAnchor constraintEqualToAnchor:_iconPreview.leadingAnchor constant:-12],
        [_iconField.heightAnchor constraintEqualToConstant:38],
        [_iconPreview.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_iconPreview.centerYAnchor constraintEqualToAnchor:_iconField.centerYAnchor],
        [_iconPreview.widthAnchor constraintEqualToConstant:30],
        [_iconPreview.heightAnchor constraintEqualToConstant:30],
        [urlCaption.topAnchor constraintEqualToAnchor:_iconField.bottomAnchor constant:16],
        [urlCaption.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [urlCaption.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_urlField.topAnchor constraintEqualToAnchor:urlCaption.bottomAnchor constant:6],
        [_urlField.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [_urlField.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_urlField.heightAnchor constraintEqualToConstant:38],
    ]];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [footer.topAnchor constraintEqualToAnchor:_urlField.bottomAnchor constant:24],
        [footer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [footer.widthAnchor constraintEqualToConstant:260],
        [footer.heightAnchor constraintEqualToConstant:44],
        [deleteButton.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [deleteButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
    ]];
    [self pxIconChanged:_iconField];
}

- (UILabel *)pxCaptionLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = [UIColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UITextField *)pxTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    field.placeholder = placeholder;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (void)pxIconChanged:(UITextField *)sender {
    NSString *symbol = [sender.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UIImage *preview = symbol.length > 0 ? [UIImage systemImageNamed:symbol] : nil;
    self.iconPreview.image = preview;
    self.iconField.textColor = symbol.length > 0 && !preview ? UIColor.systemRedColor : UIColor.labelColor;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)pxCancelTapped:(UIBarButtonItem *)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)pxDeleteTapped:(UIButton *)sender {
    if (!self.button || !self.onDelete) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除此按钮"
        message:self.button.name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            void (^onDelete)(void) = self.onDelete;
            [self.navigationController popViewControllerAnimated:YES];
            if (onDelete) onDelete();
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pxSaveTapped:(UIBarButtonItem *)sender {
    [self.view endEditing:YES];
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *icon = [self.iconField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *url = [self.urlField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0 || url.length == 0) {
        [self pxShowInvalidAlert:@"名称与 URL 均为必填。"];
        return;
    }
    if (icon.length > 0 && ![UIImage systemImageNamed:icon]) {
        [self pxShowInvalidAlert:@"SF 图标名称无效，请检查或留空显示文字。"];
        return;
    }
    PXCustomSelectionButton *saved = [PXEditorOrder saveCustomSelectionButtonWithID:self.button.identifier
                                                                               name:name
                                                                               icon:icon
                                                                                url:url];
    if (!saved) {
        [self pxShowInvalidAlert:@"URL 无效：需要带 scheme 的完整地址（例如 shortcuts://…）。"];
        return;
    }
    PXLogInfo(@"prefs custom url saved: %@", saved.identifier);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)pxShowInvalidAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法保存"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
