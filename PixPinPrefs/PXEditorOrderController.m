#import "PXEditorOrderController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

@interface PXEditorOrderController ()
// 必须 strong：copy 语义会把 NSMutableArray 存成不可变 NSArray，拖动时 removeObjectAtIndex 直接崩溃。
@property (nonatomic, strong) NSMutableArray<NSString *> *actionOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *toolOrder;
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
    // 拖动手柄需要编辑模式；无插入/删除样式，单元格不显示增删控件。
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = NO;
}

- (void)pxReloadFromPreferences {
    self.actionOrder = [[PXEditorOrder currentActionOrder] mutableCopy];
    self.toolOrder = [[PXEditorOrder currentToolOrder] mutableCopy];
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
        return @"按住右侧手柄上下拖动调整顺序，修改即时保存，编辑器下次打开生效。区域/冻结/即时编辑不含“面板停靠”和“收起面板”。";
    }
    return @"排序同时应用于区域编辑和全屏标记的工具面板。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *reuse = @"PXEditorOrderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
    }
    cell.textLabel.text = [self displayNameForIdentifier:[self identifierAtIndexPath:indexPath]
                                                 section:indexPath.section];
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
    [self pxPersistOrder];
}

#pragma mark - 持久化

- (void)pxPersistOrder {
    [PXEditorOrder saveActionOrderString:[PXEditorOrder stringForOrder:self.actionOrder]];
    [PXEditorOrder saveToolOrderString:[PXEditorOrder stringForOrder:self.toolOrder]];
    PXLogInfo(@"prefs editor order saved: actions=%@ tools=%@",
              [PXEditorOrder stringForOrder:self.actionOrder],
              [PXEditorOrder stringForOrder:self.toolOrder]);
}

- (void)pxResetTapped:(UIBarButtonItem *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认排序"
                                                                   message:@"操作按钮和工具按钮都会恢复为默认顺序。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [PXEditorOrder saveActionOrderString:nil];
        [PXEditorOrder saveToolOrderString:nil];
        [self pxReloadFromPreferences];
        [self.tableView reloadData];
        PXLogInfo(@"prefs editor order reset to defaults");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
