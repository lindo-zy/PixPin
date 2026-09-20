#import "PXHistoryViewController.h"
#import "PXHistoryItem.h"
#import "PXHistoryStore.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"

static const CGFloat PXHistoryHeaderHeight = 48.0;

@interface PXHistoryViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<PXHistoryItem *> *items;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@end

@implementation PXHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    self.items = @[];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pxHistoryChanged:)
                                                 name:PXNotificationHistoryChanged
                                               object:nil];

    [self pxBuildHeader];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 64.0;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = @"暂无截图历史";
    _emptyLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.hidden = YES;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:PXHistoryHeaderHeight],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self pxReloadItems];
}

- (void)pxBuildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, PXHistoryHeaderHeight)];
    header.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.tintColor = [UIColor whiteColor];
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [closeButton addTarget:self action:@selector(pxCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:closeButton];

    _headerTitleLabel = [[UILabel alloc] init];
    _headerTitleLabel.text = @"截图历史";
    _headerTitleLabel.textColor = [UIColor whiteColor];
    _headerTitleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _headerTitleLabel.textAlignment = NSTextAlignmentCenter;
    _headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:_headerTitleLabel];

    UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    clearButton.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
    [clearButton setTitle:@"清空" forState:UIControlStateNormal];
    clearButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [clearButton addTarget:self action:@selector(pxClearTapped:) forControlEvents:UIControlEventTouchUpInside];
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:clearButton];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:PXHistoryHeaderHeight],

        [closeButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [closeButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [_headerTitleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [_headerTitleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [clearButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [clearButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
}

#pragma mark - 数据

- (void)pxReloadItems {
    // Store 的读接口本身是锁内快照，直接取。
    self.items = [PXHistoryStore sharedStore].allItems;
    [self.tableView reloadData];
    self.emptyLabel.hidden = (self.items.count > 0);
}

- (void)pxHistoryChanged:(NSNotification *)notification {
    if ([self isViewLoaded]) {
        [self pxReloadItems];
    }
}

#pragma mark - 头部动作

- (void)pxCloseTapped:(UIButton *)sender {
    if (self.delegate && [self.delegate respondsToSelector:@selector(historyViewControllerDidClose:)]) {
        [self.delegate historyViewControllerDidClose:self];
    }
}

- (void)pxClearTapped:(UIButton *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空历史"
                                                                   message:@"将删除全部历史记录与图片，无法恢复。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[PXHistoryStore sharedStore] clearAllWithCompletion:^{
            [self pxReloadItems];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"PXHistoryCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.imageView.layer.cornerRadius = 6.0;
        cell.imageView.clipsToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    }

    PXHistoryItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.isEdited ? [item.displayName stringByAppendingString:@" · 已编辑"] : item.displayName;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm:ss";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %ld×%ld",
                                 [formatter stringFromDate:item.createdAt],
                                 (long)item.pixelWidth, (long)item.pixelHeight];
    if (item.thumbnailPath) {
        cell.imageView.image = [UIImage imageWithContentsOfFile:item.thumbnailPath];
    } else {
        cell.imageView.image = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PXHistoryItem *item = self.items[indexPath.row];
    if (self.delegate && [self.delegate respondsToSelector:@selector(historyViewController:didRequestReeditOfItem:)]) {
        [self.delegate historyViewController:self didRequestReeditOfItem:item];
    }
}

- (void)tableView:(UITableView *)tableView
  commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
   forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    PXHistoryItem *item = self.items[indexPath.row];
    [[PXHistoryStore sharedStore] removeItemWithID:item.historyID completion:nil];
    NSMutableArray<PXHistoryItem *> *updated = [self.items mutableCopy];
    [updated removeObjectAtIndex:indexPath.row];
    self.items = updated;
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    self.emptyLabel.hidden = (self.items.count > 0);
    PXLogInfo(@"history item removed: %@", item.historyID);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.items = @[];
}

@end
