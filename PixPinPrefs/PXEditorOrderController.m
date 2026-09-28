#import "PXEditorOrderController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

@interface PXEditorOrderController ()
// 必须 strong：copy 语义会把 NSMutableArray 存成不可变 NSArray，拖动时 removeObjectAtIndex 直接崩溃。
@property (nonatomic, strong) NSMutableArray<NSString *> *actionOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *toolOrder;
@property (nonatomic, strong) NSMutableSet<NSString *> *actionHidden;
@property (nonatomic, strong) NSMutableSet<NSString *> *toolHidden;
@end

@implementation PXEditorOrderController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
        self.title = @"编辑器按钮排序";
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"恢复默认"
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(pxResetTapped:)];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self pxReloadFromPreferences];
    // 拖动手柄需要编辑模式；无插入/删除样式，单元格不显示增删控件。开关在 accessoryView，编辑模式仍可点。
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = NO;
}

- (void)pxReloadFromPreferences {
    self.actionOrder = [[PXEditorOrder currentActionOrder] mutableCopy];
    self.toolOrder = [[PXEditorOrder currentToolOrder] mutableCopy];
    self.actionHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentActionHidden]];
    self.toolHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentToolHidden]];
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.actionOrder.count : self.toolOrder.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"操作按钮（面板停靠、收起面板仅全屏标记显示）";
    return @"工具按钮";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"按住右侧手柄拖动调整顺序，开关控制按钮是否在编辑器显示，修改即时保存、下次打开编辑器生效。“关闭”和“完成”是编辑器唯一出口，始终显示；区域/冻结/即时编辑不含“面板停靠”和“收起面板”。";
    }
    return @"排序与显隐同时应用于区域编辑和全屏标记的工具面板；全部工具关闭时编辑器会回退为显示全部工具。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *reuse = @"PXEditorOrderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    }
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSString *displayName = [self displayNameForIdentifier:identifier section:indexPath.section];
    cell.textLabel.text = displayName;
    NSString *iconName = indexPath.section == 0
        ? [PXEditorOrder iconNameForActionIdentifier:identifier]
        : [PXEditorOrder iconNameForToolIdentifier:identifier];
    cell.imageView.image = iconName.length
        ? [UIImage systemImageNamed:iconName]
        : nil;

    UISwitch *toggle = (UISwitch *)cell.accessoryView;
    if (![toggle isKindOfClass:[UISwitch class]]) {
        toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(pxVisibilityChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    // 复用会换行，开关的无障碍名称必须每次随行重设。
    toggle.accessibilityLabel = [NSString stringWithFormat:@"显示%@", displayName ?: @""];
    BOOL alwaysVisible = (indexPath.section == 0 && ([identifier isEqualToString:@"close"] ||
                                                     [identifier isEqualToString:@"done"]));
    toggle.on = ![self isHiddenIdentifier:identifier section:indexPath.section];
    toggle.enabled = !alwaysVisible;
    cell.showsReorderControl = YES;
    return cell;
}

- (NSString *)identifierAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? self.actionOrder[indexPath.row] : self.toolOrder[indexPath.row];
}

- (NSString *)displayNameForIdentifier:(NSString *)identifier section:(NSInteger)section {
    return section == 0
        ? [PXEditorOrder displayNameForActionIdentifier:identifier]
        : [PXEditorOrder displayNameForToolIdentifier:identifier];
}

- (BOOL)isHiddenIdentifier:(NSString *)identifier section:(NSInteger)section {
    return [section == 0 ? self.actionHidden : self.toolHidden containsObject:identifier];
}

#pragma mark - 显隐开关

- (void)pxVisibilityChanged:(UISwitch *)sender {
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds))
                                  toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return;
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSMutableSet<NSString *> *hidden = indexPath.section == 0 ? self.actionHidden : self.toolHidden;
    if (sender.on) {
        [hidden removeObject:identifier];
    } else {
        [hidden addObject:identifier];
    }
    [self pxPersistAll];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - 拖动排序

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

// 只允许同分组内移动，跨组拖动落点无效。
- (NSIndexPath *)tableView:(UITableView *)tableView
   targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                          toProposedIndexPath:(NSIndexPath *)proposedIndexPath {
    if (sourceIndexPath.section != proposedIndexPath.section) return sourceIndexPath;
    return proposedIndexPath;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray<NSString *> *order = sourceIndexPath.section == 0 ? self.actionOrder : self.toolOrder;
    NSString *identifier = order[sourceIndexPath.row];
    [order removeObjectAtIndex:sourceIndexPath.row];
    [order insertObject:identifier atIndex:destinationIndexPath.row];
    [self pxPersistAll];
}

#pragma mark - 持久化

- (void)pxPersistAll {
    [PXEditorOrder saveActionOrderString:[PXEditorOrder stringForOrder:self.actionOrder]];
    [PXEditorOrder saveToolOrderString:[PXEditorOrder stringForOrder:self.toolOrder]];
    [PXEditorOrder saveActionHiddenString:[PXEditorOrder stringForOrder:self.actionHidden.allObjects]];
    [PXEditorOrder saveToolHiddenString:[PXEditorOrder stringForOrder:self.toolHidden.allObjects]];
    PXLogInfo(@"prefs editor buttons saved: actions=%@ hidden=%@ tools=%@ hidden=%@",
              [PXEditorOrder stringForOrder:self.actionOrder],
              [PXEditorOrder stringForOrder:self.actionHidden.allObjects],
              [PXEditorOrder stringForOrder:self.toolOrder],
              [PXEditorOrder stringForOrder:self.toolHidden.allObjects]);
}

- (void)pxResetTapped:(UIBarButtonItem *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认"
                                                                   message:@"操作按钮和工具按钮都会恢复为默认顺序并全部显示。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [PXEditorOrder saveActionOrderString:nil];
        [PXEditorOrder saveToolOrderString:nil];
        [PXEditorOrder saveActionHiddenString:nil];
        [PXEditorOrder saveToolHiddenString:nil];
        [self pxReloadFromPreferences];
        [self.tableView reloadData];
        PXLogInfo(@"prefs editor buttons reset to defaults");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
