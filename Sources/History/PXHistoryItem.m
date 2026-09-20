#import "PXHistoryItem.h"
#import "../Common/PXConstants.h"

@implementation PXHistoryItem

+ (instancetype)itemWithImage:(UIImage *)image
                         mode:(PXCaptureMode)mode
                     isEdited:(BOOL)isEdited
     originalAssetIdentifier:(NSString *)originalAssetIdentifier {
    PXHistoryItem *item = [[PXHistoryItem alloc] init];
    item.historyID = [[NSUUID UUID] UUIDString];
    item.createdAt = [NSDate date];
    item.mode = mode;
    item.isEdited = isEdited;
    item.originalAssetIdentifier = originalAssetIdentifier;
    // pixelWidth/Height 由调用方填写（本文件保持无 UIKit 依赖，可在宿主上测试）。
    return item;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"historyID": self.historyID ?: @"",
        @"createdAt": @([self.createdAt timeIntervalSince1970]),
        @"mode": @(self.mode),
        @"originalAssetIdentifier": self.originalAssetIdentifier ?: @"",
        @"editedAssetIdentifier": self.editedAssetIdentifier ?: @"",
        @"thumbnailPath": self.thumbnailPath ?: @"",
        @"originalPath": self.originalPath ?: @"",
        @"editedPath": self.editedPath ?: @"",
        @"pixelWidth": @(self.pixelWidth),
        @"pixelHeight": @(self.pixelHeight),
        @"isEdited": @(self.isEdited),
    };
}

+ (nullable instancetype)itemWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    NSString *historyID = dictionary[@"historyID"];
    if (historyID.length == 0) return nil;

    PXHistoryItem *item = [[PXHistoryItem alloc] init];
    item.historyID = historyID;
    double timestamp = [dictionary[@"createdAt"] doubleValue];
    item.createdAt = timestamp > 0 ? [NSDate dateWithTimeIntervalSince1970:timestamp] : [NSDate date];
    item.mode = (PXCaptureMode)[dictionary[@"mode"] integerValue];
    item.originalAssetIdentifier = [dictionary[@"originalAssetIdentifier"] length] > 0 ? dictionary[@"originalAssetIdentifier"] : nil;
    item.editedAssetIdentifier = [dictionary[@"editedAssetIdentifier"] length] > 0 ? dictionary[@"editedAssetIdentifier"] : nil;
    item.thumbnailPath = [dictionary[@"thumbnailPath"] length] > 0 ? dictionary[@"thumbnailPath"] : nil;
    item.originalPath = [dictionary[@"originalPath"] length] > 0 ? dictionary[@"originalPath"] : nil;
    item.editedPath = [dictionary[@"editedPath"] length] > 0 ? dictionary[@"editedPath"] : nil;
    item.pixelWidth = [dictionary[@"pixelWidth"] integerValue];
    item.pixelHeight = [dictionary[@"pixelHeight"] integerValue];
    item.isEdited = [dictionary[@"isEdited"] boolValue];
    return item;
}

- (NSString *)displayName {
    switch (self.mode) {
        case PXCaptureModeFull: return @"全屏截图";
        case PXCaptureModeArea: return @"区域截图";
        case PXCaptureModeFreeze: return @"冻结截图";
        case PXCaptureModeInstant: return @"即时截图";
    }
    return @"截图";
}

@end
