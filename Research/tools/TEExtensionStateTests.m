// 仅在独立进程创建离屏 UIImageView；不安装 Hook、不显示窗口、不读写屏幕。
#import "../../Sources/TEExtensions.m"
NSString *TEBootstrapFilePath(NSString *path) { return ApelinBootstrapPath(path); }
void MSHookMessageEx(Class cls, SEL cmd, IMP hook, IMP *original) {
    (void)cls; (void)cmd; (void)hook; (void)original;
    abort(); // 本测试不应安装任何 Hook。
}
static int checks, failures;
static void Check(BOOL result, const char *message) { checks++; if (!result) failures++; printf("%s %s\n", result ? "PASS" : "FAIL", message); }
static UIImage *Solid(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20, 20)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [color setFill]; UIRectFill(CGRectMake(0, 0, 20, 20));
    }];
}
int main(void) {
    @autoreleasepool {
        UIImage *original = Solid(UIColor.whiteColor), *replacement = Solid(UIColor.redColor), *systemUpdate = Solid(UIColor.greenColor);
        UIImageView *view = [[UIImageView alloc] initWithImage:original];
        TEOverrideImage(view, replacement);
        Check(view.image == replacement, "视图接入主题图片");
        TEOverrideImage(view, nil);
        Check(view.image == original, "停用恢复原图");
        TEOverrideImage(view, replacement); view.image = systemUpdate;
        TEOverrideImage(view, nil);
        Check(view.image == systemUpdate, "停用不覆盖系统后来更新的图片");
        view.image = original;
        TEApplyBadgeTextColor(view, @{@"TextColor":@"#123456"});
        UIImage *tinted = view.image;
        Check(tinted != original, "已缓存原生文字也能生成主题着色副本");
        TEApplyBadgeTextColor(view, @{@"TextColor":@"#123456"});
        Check(view.image == tinted, "重复布局复用文字着色图");
        TEApplyBadgeTextColor(view, @{@"TextColor":@"#654321"});
        Check(view.image != tinted, "切换文字颜色更新副本");
        TEApplyBadgeTextColor(view, @{});
        Check(view.image == original, "停用文字颜色恢复原生缓存图");
        view.frame = CGRectMake(10, 10, 20, 20);
        TEApplyTextOffset(view, @{@"TextXoffset":@2,@"TextYoffset":@3});
        Check(view.frame.origin.x == 12 && view.frame.origin.y == 13, "主题文字位置偏移生效");
        TEApplyTextOffset(view, @{@"TextXoffset":@2,@"TextYoffset":@3});
        Check(view.frame.origin.x == 12 && view.frame.origin.y == 13, "反复布局不累计偏移");
        TEApplyTextOffset(view, @{});
        Check(view.frame.origin.x == 10 && view.frame.origin.y == 10, "停用位置偏移恢复基准");
        view.frame = CGRectMake(30, 40, 20, 20);
        TEApplyTextOffset(view, @{@"TextXoffset":@2});
        Check(view.frame.origin.x == 32 && view.frame.origin.y == 40, "系统重新布局后使用新基准");
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
