#import <Foundation/Foundation.h>
#import "../Common/PXGeometry.h"

@class UIImage;

NS_ASSUME_NONNULL_BEGIN

/// 历史条目：图片文件由 PXHistoryStore 拷贝进历史目录自持，不依赖任务临时目录。
@interface PXHistoryItem : NSObject

@property (nonatomic, copy) NSString *historyID;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) PXCaptureMode mode;
@property (nonatomic, copy, nullable) NSString *originalAssetIdentifier;
@property (nonatomic, copy, nullable) NSString *editedAssetIdentifier;
@property (nonatomic, copy, nullable) NSString *thumbnailPath;
@property (nonatomic, copy, nullable) NSString *originalPath;
@property (nonatomic, copy, nullable) NSString *editedPath;
@property (nonatomic, assign) NSInteger pixelWidth;
@property (nonatomic, assign) NSInteger pixelHeight;
@property (nonatomic, assign) BOOL isEdited;

+ (instancetype)itemWithImage:(UIImage *)image
                         mode:(PXCaptureMode)mode
                     isEdited:(BOOL)isEdited
     originalAssetIdentifier:(nullable NSString *)originalAssetIdentifier;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)itemWithDictionary:(NSDictionary *)dictionary;
- (NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
