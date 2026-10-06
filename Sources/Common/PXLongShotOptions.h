#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PXLongShotMode) {
    PXLongShotModeSampling = 0,
    PXLongShotModeSmart = 1,
    PXLongShotModeAutomatic = 2,
};
/// 每个任务的不可变参数快照；内存安全底线不属于可配置项。
@interface PXLongShotOptions : NSObject
@property (nonatomic, readonly) PXLongShotMode mode;
@property (nonatomic, readonly) BOOL autoScroll; // 兼容旧调用者：智能与自动均使用短滑
@property (nonatomic, readonly) BOOL keepFrames;
@property (nonatomic, readonly) NSTimeInterval sampleInterval;
@property (nonatomic, readonly) NSTimeInterval idleInterval;
@property (nonatomic, readonly) NSTimeInterval scrollDuration;
@property (nonatomic, readonly) NSTimeInterval settleDuration;
@property (nonatomic, readonly) NSInteger maxSlices;
@property (nonatomic, readonly) NSInteger maxCanvasHeight;
@property (nonatomic, readonly) double sliceQuality;
@property (nonatomic, readonly) double outputQuality;
- (instancetype)initWithValues:(NSDictionary<NSString *, id> *)values;
+ (NSArray<NSString *> *)preferenceKeys;
@end
NS_ASSUME_NONNULL_END
