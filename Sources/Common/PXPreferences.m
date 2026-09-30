#import "PXPreferences.h"
#import "PXConstants.h"
#import "PXLog.h"

// .m 内部可写版本：加载时一次性填充，之后只读。
@interface PXConfig ()
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) PXOutputAction defaultResultAction;
@property (nonatomic, readwrite) BOOL showResultBubble;
@property (nonatomic, readwrite) BOOL screenshotHaptic;
@property (nonatomic, readwrite) BOOL areaRememberLastRect;
@property (nonatomic, readwrite) CGFloat editorDefaultLineWidth;
@end

@implementation PXConfig

- (instancetype)initDefault {
    if (self = [super init]) {
        _enabled = YES;
        _defaultResultAction = (PXOutputAction)PXDefaultResultAction;
        _showResultBubble = YES;
        _screenshotHaptic = YES;
        _areaRememberLastRect = NO;
        _editorDefaultLineWidth = PXDefaultEditorLineWidth;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<PXConfig enabled=%d action=%ld bubble=%d haptic=%d rememberRect=%d lineWidth=%.1f>",
            self.enabled, (long)self.defaultResultAction,
            self.showResultBubble, self.screenshotHaptic, self.areaRememberLastRect,
            self.editorDefaultLineWidth];
}

@end

static BOOL PXPrefBool(NSString *key, BOOL defaultValue) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)PXPreferencesDomain,
                                                    &valid);
    return valid ? (BOOL)value : defaultValue;
}

static NSInteger PXPrefInteger(NSString *key, NSInteger defaultValue) {
    Boolean valid = false;
    CFIndex value = CFPreferencesGetAppIntegerValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)PXPreferencesDomain,
                                                    &valid);
    return valid ? (NSInteger)value : defaultValue;
}

static CGFloat PXPrefDouble(NSString *key, CGFloat defaultValue) {
    id obj = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)PXPreferencesDomain));
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)obj doubleValue];
    }
    return defaultValue;
}

@implementation PXPreferences

static PXConfig *_currentConfig = nil;

+ (PXConfig *)config {
    @synchronized(self) {
        if (!_currentConfig) {
            [self reload];
        }
        return _currentConfig;
    }
}

+ (void)reload {
    PXConfig *config = [[PXConfig alloc] initDefault];

    config.enabled = PXPrefBool(PXKeyEnabled, YES);
    config.showResultBubble = PXPrefBool(PXKeyShowResultBubble, YES);
    config.screenshotHaptic = PXPrefBool(PXKeyScreenshotHaptic, YES);
    config.areaRememberLastRect = PXPrefBool(PXKeyAreaRememberLastRect, NO);

    NSInteger action = PXPrefInteger(PXKeyDefaultResultAction, PXDefaultResultAction);
    config.defaultResultAction = (PXOutputAction)MAX(0, MIN(4, action));

    CGFloat lineWidth = PXPrefDouble(PXKeyEditorDefaultLineWidth, PXDefaultEditorLineWidth);
    config.editorDefaultLineWidth = MAX(0.5, MIN(16.0, lineWidth));

    @synchronized(self) {
        _currentConfig = config;
    }
    PXLogInfo(@"config reloaded: %@", config);
}

@end
