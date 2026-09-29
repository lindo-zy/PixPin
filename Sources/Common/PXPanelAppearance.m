#import "PXPanelAppearance.h"
#import "PXConstants.h"
#import <math.h>

static NSString *const PXPanelTintKey = @"MarkupPanelTintRGBA";

@implementation PXPanelAppearance

+ (UIColor *)tintColor {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)PXPanelTintKey,
                                                        (__bridge CFStringRef)PXPreferencesDomain));
    if ([value isKindOfClass:NSArray.class] && [value count] == 4) {
        BOOL valid = YES;
        for (id component in value) {
            if (![component isKindOfClass:NSNumber.class] || !isfinite([component doubleValue]) ||
                [component doubleValue] < 0 || [component doubleValue] > 1) {
                valid = NO;
                break;
            }
        }
        if (valid) return [UIColor colorWithRed:[value[0] doubleValue] green:[value[1] doubleValue]
                                         blue:[value[2] doubleValue] alpha:[value[3] doubleValue]];
    }
    return [UIColor colorWithRed:0.02 green:0.23 blue:0.22 alpha:0.28];
}

+ (void)setTintColor:(UIColor *)color {
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return;
    NSArray *components = @[@(r), @(g), @(b), @(a)];
    CFPreferencesSetAppValue((__bridge CFStringRef)PXPanelTintKey, (__bridge CFArrayRef)components,
                            (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         PXDarwinPreferencesReload, NULL, NULL, YES);
}

+ (void)installBackgroundInView:(UIView *)view {
    view.backgroundColor = UIColor.clearColor;
    view.clipsToBounds = YES;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.userInteractionEnabled = NO;
    // 调色层必须位于模糊材质上方；容器底色会被材质遮盖。
    blur.contentView.backgroundColor = [self tintColor];
    blur.layer.cornerRadius = view.layer.cornerRadius;
    blur.clipsToBounds = YES;
    [view insertSubview:blur atIndex:0];
}

@end
