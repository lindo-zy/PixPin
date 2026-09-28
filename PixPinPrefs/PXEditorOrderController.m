#import "PXEditorOrderController.h"
#import "PXEditorButtonEditController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

@interface PXEditorOrderController ()
// 必须 strong：copy 语义会把 NSMutableArray 存成不可变 NSArray，拖动时 removeObjectAtIndex 直接崩溃。
@property (nonatomic, strong) NSMutableArray<NSString *> *actionOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *toolOrder;
@property (nonatomic, strong) NSMutableSet<NSString *> *actionHidden;
@property (nonatomic, strong) NSMutableSet<NSString *> *toolHidden;
@property (nonatomic, weak) UILabel *sizeValueLabel;
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
    // 拖动手柄需要编辑模式；无插入/删除样式。开关在 accessoryView，编辑模式仍可点；行点击进图标/名称编辑。
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (void)pxReloadFromPreferences {
    self.actionOrder = [[PXEditorOrder currentActionOrder] mutableCopy];
    self.toolOrder = [[PXEditorOrder currentToolOrder] mutableCopy];
    self.actionHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentActionHidden]];
    self.toolHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentToolHidden]];
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.actionOrder.count;
    if (section == 1) return self.toolOrder.count;
    return 1;   // 外观：图标大小
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"操作按钮（面板停靠、收起面板仅全屏标记显示）";
    if (section == 1) return @"工具按钮";
    return @"外观";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"拖动手柄调整顺序，开关控制按钮是否在编辑器显示，点击行可修改图标与名称；修改即时保存，编辑器下次打开生效。“关闭”和“完成”是编辑器唯一出口，始终显示；区域/冻结/即时编辑不含“面板停靠”和“收起面板”。";
    }
    if (section == 1) {
        return @"排序、显隐与自定义图标/名称同时应用于区域编辑和全屏标记的工具面板；全部工具关闭时编辑器会回退为显示全部工具。";
    }
    return @"调整编辑器按钮图标的显示大小。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        return [self pxSliderCellForTableView:tableView];
    }

    NSString *reuse = @"PXEditorOrderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSString *displayName = [self displayNameForIdentifier:identifier section:indexPath.section];
    cell.textLabel.text = displayName;
    cell.detailTextLabel.text = @"点击修改图标与名称";
    NSString *iconName = indexPath.section == 0
        ? [PXEditorOrder iconNameForActionIdentifier:identifier]
        : [PXEditorOrder iconNameForToolIdentifier:identifier];
    cell.imageView.image = iconName.length ? [UIImage systemImageNamed:iconName] : nil;

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

- (UITableViewCell *)pxSliderCellForTableView:(UITableView *)tableView {
    NSString *reuse = @"PXEditorSizeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
        cell.textLabel.text = @"按钮图标大小";
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 31)];
        slider.minimumValue = 12.0;
        slider.maximumValue = 28.0;
        [slider addTarget:self action:@selector(pxIconSizeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        self.sizeValueLabel = cell.detailTextLabel;
    }
    UISlider *slider = (UISlider *)cell.accessoryView;
    CGFloat size = [PXEditorOrder buttonIconPointSize];
    if (slider.value != size) slider.value = size;   // 拖动中重入时避免打断
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
    // 复用路径也会走这里，弱引用必须每次重绑到当前 cell 的标签。
    self.sizeValueLabel = cell.detailTextLabel;
    cell.showsReorderControl = NO;
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

#pragma mark - 行点击：编辑图标与名称

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.section >= 2) return;
    [self.view endEditing:YES];

    NSString *identifier = [self identifierAtIndexPath:indexPath];
    BOOL isAction = indexPath.section == 0;
    NSString *defaultIcon = isAction
        ? [PXEditorOrder defaultIconNameForActionIdentifier:identifier]
        : [PXEditorOrder defaultIconNameForToolIdentifier:identifier];
    NSString *customIcon = isAction
        ? [PXEditorOrder customIconNameForActionIdentifier:identifier]
        : [PXEditorOrder customIconNameForToolIdentifier:identifier];
    NSString *customName = isAction
        ? [PXEditorOrder customNameForActionIdentifier:identifier]
        : [PXEditorOrder customNameForToolIdentifier:identifier];

    PXEditorButtonEditController *editor =
        [[PXEditorButtonEditController alloc] initWithIdentifier:identifier
                                                       isAction:isAction
                                                    displayName:[self displayNameForIdentifier:identifier section:indexPath.section]
                                                defaultIconName:defaultIcon
                                                     customName:customName
                                                 customIconName:customIcon
                                                         onSave:^(NSString *name, NSString *iconName) {
            if (isAction) {
                [PXEditorOrder saveActionName:name forIdentifier:identifier];
                [PXEditorOrder saveActionIconName:iconName forIdentifier:identifier];
            } else {
                [PXEditorOrder saveToolName:name forIdentifier:identifier];
                [PXEditorOrder saveToolIconName:iconName forIdentifier:identifier];
            }
            PXLogInfo(@"prefs editor button override saved: %@ name=%@ icon=%@", identifier, name, iconName);
            [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationNone];
            [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        }];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:editor]
                       animated:YES completion:nil];
}

#pragma mark - 显隐开关

- (void)pxVisibilityChanged:(UISwitch *)sender {
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds))
                                  toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.section >= 2) return;
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

#pragma mark - 图标大小

- (void)pxIconSizeChanged:(UISlider *)sender {
    CGFloat size = MAX(12.0, MIN(28.0, sender.value));
    [PXEditorOrder saveButtonIconPointSize:size];
    self.sizeValueLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
}

#pragma mark - 拖动排序

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section < 2;
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
                                                                   message:@"顺序、显隐、自定义图标/名称和图标大小都会恢复默认。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [PXEditorOrder saveActionOrderString:nil];
        [PXEditorOrder saveToolOrderString:nil];
        [PXEditorOrder saveActionHiddenString:nil];
        [PXEditorOrder saveToolHiddenString:nil];
        for (NSString *identifier in [PXEditorOrder defaultActionIdentifiers]) {
            [PXEditorOrder saveActionName:nil forIdentifier:identifier];
            [PXEditorOrder saveActionIconName:nil forIdentifier:identifier];
        }
        for (NSString *identifier in [PXEditorOrder defaultToolIdentifiers]) {
            [PXEditorOrder saveToolName:nil forIdentifier:identifier];
            [PXEditorOrder saveToolIconName:nil forIdentifier:identifier];
        }
        [PXEditorOrder saveButtonIconPointSize:17.0];
        [self pxReloadFromPreferences];
        [self.tableView reloadData];
        PXLogInfo(@"prefs editor buttons reset to defaults");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
