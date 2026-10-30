// Pineora 偏好包根控制器。
//
// 保持 PSListController，PreferenceLoader 的入口才能打开它；Root.plist 只给标题，
// 行由子控制器 PineoraSettingsController 画，它的表格盖住列表自带的表格（与 DockFlip 相同做法）。
#import <Preferences/PSListController.h>
#import "PineoraSettingsController.h"

// Preferences.framework 运行时提供；这里只为编译器声明。
@interface PSListController (PineoraPrivate)
- (UITableView *)table;
@end

@interface PineoraRootListController : PSListController
@property (nonatomic, strong) PineoraSettingsController *page;
@end

@implementation PineoraRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.title.length == 0) {
        self.title = @"Pineora";
    }
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UITableView *listTable = [self respondsToSelector:@selector(table)] ? [self table] : nil;
    listTable.hidden = YES;
    listTable.scrollsToTop = NO;

    PineoraSettingsController *page = [[PineoraSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self addChildViewController:page];
    page.view.frame = self.view.bounds;
    page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:page.view];
    [page didMoveToParentViewController:self];
    self.page = page;

    self.navigationItem.rightBarButtonItem = page.editButtonItem;
    [self setContentScrollView:page.tableView forEdge:NSDirectionalRectEdgeAll];
    NSLog(@"[PineoraPrefs] root pane loaded");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从别处回来时主题目录或设置可能变了。
    [self.page reloadFromStore];
}

@end
