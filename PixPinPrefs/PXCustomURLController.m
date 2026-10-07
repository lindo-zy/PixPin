#import <Preferences/PSViewController.h>
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

// 自定义 URL 按钮管理：设置页增删改任意个 URL scheme 快捷按钮，
// 按钮出现在截图按钮工具栏，点击后取消当前截图并经 SpringBoard openURL 打开。
// 与 PXEditorOrderController 同款自建 UITableView；Preferences 导航页必须继承
// PSViewController，提供 PSLinkCell 所需的 specifier / parentController 与生命周期接口。
// 编辑页同样用 inset grouped 表格承载表单行：真机实测绝对约束表单在
// PSNavigationController 里会整页叠印（2.1.0/2.1.1 两版复现），行布局交给 UIKit。

@interface PXCustomURLController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@end

@interface PXCustomURLEditController : PSViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
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

// 表单分节：0=显示名称 1=SF 图标 2=URL 3=删除（仅编辑已有按钮时出现）。
@interface PXCustomURLEditController ()
@property (nonatomic, strong, nullable) PXCustomSelectionButton *button;
@property (nonatomic, copy, nullable) void (^onDelete)(void);
@property (nonatomic, strong) UITableView *formTable;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *iconField;
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

- (void)loadView {
    _formTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _formTable.dataSource = self;
    _formTable.delegate = self;
    _formTable.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.view = _formTable;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = self.button ? @"编辑按钮" : @"添加按钮";
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(pxCancelTapped:)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(pxSaveTapped:)];

    _nameField = [self pxFieldWithPlaceholder:@"例如：翻译" keyboard:UIKeyboardTypeDefault];
    _nameField.text = self.button.name ?: @"";

    _iconField = [self pxFieldWithPlaceholder:@"例如：arrow.up.right" keyboard:UIKeyboardTypeASCIICapable];
    _iconField.text = self.button.iconName.length > 0 ? self.button.iconName : @"";
    [_iconField addTarget:self action:@selector(pxIconChanged:)
         forControlEvents:UIControlEventEditingChanged];

    _urlField = [self pxFieldWithPlaceholder:@"例如：shortcuts://run-shortcut?name=翻译"
                                    keyboard:UIKeyboardTypeURL];
    _urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    _urlField.text = self.button.url ?: @"";
}

- (UITextField *)pxFieldWithPlaceholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.keyboardType = keyboard;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    field.font = [UIFont systemFontOfSize:17.0];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

#pragma mark - 表格数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.button ? 4 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"显示名称（工具栏按钮文字）";
    if (section == 1) return @"SF 图标名称（留空显示文字）";
    if (section == 2) return @"URL（必填，点击按钮时打开）";
    return @"";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"填写 SF Symbols 标准图标名；无效或留空时按钮显示名称文字。";
    if (section == 2) return @"需要带 scheme 的完整地址，例如 shortcuts://run-shortcut?name=翻译，或纯 scheme 的 foxnews://。";
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *reuse = [NSString stringWithFormat:@"pxcustomurl-field-%ld", (long)indexPath.section];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UITextField *field = nil;
        if (indexPath.section == 0) {
            field = self.nameField;
        } else if (indexPath.section == 1) {
            field = self.iconField;
            UIImageView *preview = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
            preview.contentMode = UIViewContentModeScaleAspectFit;
            preview.tintColor = [UIColor systemBlueColor];
            cell.accessoryView = preview;
            [self pxRefreshIconPreviewInView:preview];
        } else if (indexPath.section == 2) {
            field = self.urlField;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.text = @"删除此按钮";
            cell.textLabel.textColor = UIColor.systemRedColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
        }
        if (field) {
            [cell.contentView addSubview:field];
            [NSLayoutConstraint activateConstraints:@[
                [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
                [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            ]];
        }
    }
    if (indexPath.section == 1) {
        UIImageView *preview = (UIImageView *)cell.accessoryView;
        if ([preview isKindOfClass:UIImageView.class]) [self pxRefreshIconPreviewInView:preview];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 48.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.section == 3) [self pxDeleteTapped:nil];
}

#pragma mark - 图标预览

// 字段行构建后从不 reload；预览视图随 cell.accessoryView 取回，离屏时 nil 各步均为无操作。
- (UIImageView *)pxIconPreviewForField:(UITextField *)field {
    UITableViewCell *cell = [_formTable cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    if ([cell.accessoryView isKindOfClass:UIImageView.class]) return (UIImageView *)cell.accessoryView;
    return nil;
}

- (void)pxRefreshIconPreviewInView:(UIImageView *)preview {
    NSString *symbol = [self.iconField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    preview.image = symbol.length > 0 ? [UIImage systemImageNamed:symbol] : nil;
    self.iconField.textColor = symbol.length > 0 && !preview.image ? UIColor.systemRedColor : UIColor.labelColor;
}

- (void)pxIconChanged:(UITextField *)sender {
    [self pxRefreshIconPreviewInView:[self pxIconPreviewForField:sender]];
}

#pragma mark - 输入

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - 动作

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
