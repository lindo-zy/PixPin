#import <UIKit/UIKit.h>
#import "../Output/PXLongImageComposer.h"
#import "../Common/PXLongShotAligner.h"

NS_ASSUME_NONNULL_BEGIN
/// 单一图像队列使用；仅最近帧签名驻留，原图逐段落盘。会话不直接修改裁片几何。
@interface PXLongShotFrameResult : NSObject
@property (nonatomic) PXLongShotFrameMatch match;
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger totalHeight;
@property (nonatomic) BOOL previewUnavailable;
@property (nonatomic, strong, nullable) UIImage *preview;
@end
@interface PXLongShotFrameStore : NSObject
- (instancetype)initWithDirectory:(NSString *)directory options:(PXLongShotOptions *)options
                     cancellation:(PXLongShotCancellation *)cancellation scale:(CGFloat)scale;
- (nullable PXLongShotFrameResult *)consumeImage:(UIImage *)image pixelRect:(CGRect)rect
                                         error:(NSError **)error;
- (void)discardPreview;
- (nullable UIImage *)exportToURL:(NSURL *)url pixelSize:(CGSize *)size
                        progress:(nullable void (^)(NSInteger, NSInteger))progress error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
