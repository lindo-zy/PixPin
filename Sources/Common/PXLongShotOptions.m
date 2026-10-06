#import "PXLongShotOptions.h"
#import "PXConstants.h"
#import <math.h>

static double PXLongShotNumber(NSDictionary *values, NSString *key, double fallback,
                                double minimum, double maximum, BOOL integer) {
    id value = values[key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return fallback;
    double number = [value doubleValue];
    if (!isfinite(number) || number < minimum || number > maximum || (integer && floor(number) != number))
        return fallback;
    return number;
}

@implementation PXLongShotOptions
+ (NSArray<NSString *> *)preferenceKeys {
    return @[PXKeyLongShotMode, PXKeyLongShotAutoScroll, PXKeyLongShotSampleInterval, PXKeyLongShotIdleInterval,
             PXKeyLongShotScrollDuration, PXKeyLongShotSettleDuration, PXKeyLongShotMaxSlices,
             PXKeyLongShotMaxCanvasHeight, PXKeyLongShotSliceQuality, PXKeyLongShotOutputQuality];
}
- (instancetype)initWithValues:(NSDictionary<NSString *, id> *)values {
    if ((self = [super init])) {
        // 新键优先；仅新键缺失时迁移旧开关。非法值回到默认自动；打开会话后仍须点截取才运行。
        id legacy = values[PXKeyLongShotAutoScroll];
        PXLongShotMode fallback = PXLongShotModeAutomatic;
        if (!values[PXKeyLongShotMode] && [legacy isKindOfClass:NSNumber.class] &&
            ([legacy doubleValue] == 0 || [legacy doubleValue] == 1))
            fallback = [legacy boolValue] ? PXLongShotModeAutomatic : PXLongShotModeSampling;
        _mode = (PXLongShotMode)PXLongShotNumber(values, PXKeyLongShotMode, fallback, 0, 2, YES);
        _autoScroll = _mode != PXLongShotModeSampling;
        _sampleInterval = PXLongShotNumber(values, PXKeyLongShotSampleInterval, 0.12, 0.08, 1, NO);
        _idleInterval = PXLongShotNumber(values, PXKeyLongShotIdleInterval, 0.5, _sampleInterval, 2, NO);
        if (_idleInterval < _sampleInterval) _idleInterval = _sampleInterval;
        _scrollDuration = PXLongShotNumber(values, PXKeyLongShotScrollDuration, 0.62, 0.25, 2, NO);
        _settleDuration = PXLongShotNumber(values, PXKeyLongShotSettleDuration, 0.7, 0.15, 2, NO); // ShellX 抬指后等 0.7s：指示条淡出+动画稳定
        _maxSlices = (NSInteger)PXLongShotNumber(values, PXKeyLongShotMaxSlices, 200, 2, 500, YES);
        _maxCanvasHeight = (NSInteger)PXLongShotNumber(values, PXKeyLongShotMaxCanvasHeight, 16384, 1024, 16384, YES);
        _sliceQuality = PXLongShotNumber(values, PXKeyLongShotSliceQuality, 0.95, 0.5, 1, NO);
        _outputQuality = PXLongShotNumber(values, PXKeyLongShotOutputQuality, 0.9, 0.5, 1, NO);
    }
    return self;
}
@end
