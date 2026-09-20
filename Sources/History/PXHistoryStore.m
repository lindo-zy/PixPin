#import "PXHistoryStore.h"
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"

static NSString * const PXHistoryIndexFileName = @"items.json";

@interface PXHistoryStore ()
@property (nonatomic, strong) NSLock *storeLock;
@property (nonatomic, strong) NSMutableArray<PXHistoryItem *> *items;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong) dispatch_queue_t ioQueue;   // 串行：磁盘 IO 与写索引
@end

@implementation PXHistoryStore

+ (instancetype)sharedStore {
    static PXHistoryStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[PXHistoryStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    if (self = [super init]) {
        _storeLock = [[NSLock alloc] init];
        _items = [[NSMutableArray alloc] init];
        _loaded = NO;
        _ioQueue = dispatch_queue_create("com.pixpin.screenshot.history.io", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - 加载

- (void)pxEnsureLoadedLocked {
    if (self.loaded) return;
    self.loaded = YES;

    NSString *indexPath = [PXHistoryDirectory() stringByAppendingPathComponent:PXHistoryIndexFileName];
    NSArray<PXHistoryItem *> *loadedItems = [self pxReadIndexFromPath:indexPath];

    if (loadedItems == nil) {
        // 索引损坏：备份后从文件反推重建，保证不崩溃。
        PXLogWarn(@"history index corrupted or missing, rebuilding from files");
        [self pxBackupCorruptIndexAtPath:indexPath];
        loadedItems = [self pxRebuildItemsFromFiles];
    }
    [self.items removeAllObjects];
    [self.items addObjectsFromArray:loadedItems];
    [self.items sortUsingComparator:^NSComparisonResult(PXHistoryItem *a, PXHistoryItem *b) {
        return [b.createdAt compare:a.createdAt];
    }];
}

- (nullable NSArray<PXHistoryItem *> *)pxReadIndexFromPath:(NSString *)path {
    @try {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) return @[];
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![object isKindOfClass:[NSArray class]]) {
            return (data.length > 0) ? nil : @[];   // 空文件视为空索引；非数组视为损坏
        }
        NSMutableArray<PXHistoryItem *> *items = [[NSMutableArray alloc] init];
        for (id entry in (NSArray *)object) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            PXHistoryItem *item = [PXHistoryItem itemWithDictionary:entry];
            if (item) [items addObject:item];
        }
        return items;
    } @catch (NSException *exception) {
        PXLogError(@"history index read exception: %@", exception);
        return nil;
    }
}

- (void)pxBackupCorruptIndexAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;
    NSString *backup = [path stringByAppendingPathExtension:@"corrupt"];
    [fm removeItemAtPath:backup error:nil];
    [fm moveItemAtPath:path toPath:backup error:nil];
}

- (NSArray<PXHistoryItem *> *)pxRebuildItemsFromFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:PXHistoryDirectory() error:nil];
    NSMutableDictionary<NSString *, PXHistoryItem *> *rebuilt = [[NSMutableDictionary alloc] init];
    for (NSString *file in files) {
        // 文件名约定：<kind>_<historyID>.jpg
        if (![file hasSuffix:@".jpg"]) continue;
        NSArray<NSString *> *parts = [file componentsSeparatedByString:@"_"];
        if (parts.count != 2) continue;
        NSString *kind = parts[0];
        NSString *historyID = [parts[1] stringByReplacingOccurrencesOfString:@".jpg" withString:@""];
        if (historyID.length < 8) continue;

        PXHistoryItem *item = rebuilt[historyID];
        if (!item) {
            item = [[PXHistoryItem alloc] init];
            item.historyID = historyID;
            item.createdAt = [NSDate date];
            item.mode = PXCaptureModeFull;
            rebuilt[historyID] = item;
        }
        NSString *path = [PXHistoryDirectory() stringByAppendingPathComponent:file];
        if ([kind isEqualToString:@"thumb"]) item.thumbnailPath = path;
        else if ([kind isEqualToString:@"original"]) item.originalPath = path;
        else if ([kind isEqualToString:@"edited"]) item.editedPath = path;
    }
    PXLogWarn(@"history rebuilt from files: %lu items", (unsigned long)rebuilt.count);
    return [rebuilt allValues];
}

#pragma mark - 增

- (void)addItem:(PXHistoryItem *)item
     sourceImage:(UIImage *)sourceImage
      limitCount:(NSInteger)limit
      completion:(void (^)(void))completion {
    if (!item) {
        if (completion) completion();
        return;
    }
    dispatch_async(self.ioQueue, ^{
        NSString *directory = PXHistoryDirectory();
        NSFileManager *fm = [NSFileManager defaultManager];

        NSString *thumbPath = [directory stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"thumb_%@.jpg", item.historyID]];
        NSString *originalPath = [directory stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"original_%@.jpg", item.historyID]];

        UIImage *decodedImage = nil;
        if (item.originalPath && [fm fileExistsAtPath:item.originalPath]) {
            // 已有落盘文件：直接拷贝字节，避免二次 JPEG 编码的质量/耗时损失。
            [fm removeItemAtPath:originalPath error:nil];
            if ([fm copyItemAtPath:item.originalPath toPath:originalPath error:nil]) {
                item.originalPath = originalPath;
                decodedImage = [UIImage imageWithContentsOfFile:originalPath];
            } else {
                // 拷贝失败必须回滚：否则条目会指向即将被清理的任务临时目录，成为永久坏条目。
                item.originalPath = nil;
            }
        } else if (sourceImage) {
            NSData *data = UIImageJPEGRepresentation(sourceImage, 0.92);
            if ([data writeToFile:originalPath atomically:YES]) {
                item.originalPath = originalPath;
                decodedImage = sourceImage;
            }
        }

        if (item.originalPath && [fm fileExistsAtPath:item.originalPath]) {
            [self pxWriteThumbnailFromFile:item.originalPath toPath:thumbPath];
            if (![fm fileExistsAtPath:thumbPath]) {
                [self pxWriteThumbnailForImage:decodedImage toPath:thumbPath];
            }
            item.thumbnailPath = [fm fileExistsAtPath:thumbPath] ? thumbPath : nil;
        } else {
            PXLogWarn(@"history item has no readable source: %@", item.historyID);
        }

        [self.storeLock lock];
        [self pxEnsureLoadedLocked];
        [self.items insertObject:item atIndex:0];

        // 超限裁剪（同时删除文件）。
        NSInteger effectiveLimit = MAX(1, limit);
        while ((NSInteger)self.items.count > effectiveLimit) {
            PXHistoryItem *removed = [self.items lastObject];
            [self.items removeLastObject];
            [self pxDeleteFilesForItem:removed];
        }

        NSArray<PXHistoryItem *> *snapshot = [self.items copy];
        [self.storeLock unlock];

        [self pxWriteIndexForItems:snapshot];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

/// 从源图文件直接产出缩略图（CGImageSource，避免为大图整图解码）。
- (void)pxWriteThumbnailFromFile:(NSString *)sourcePath toPath:(NSString *)thumbPath {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:sourcePath], NULL);
    if (!source) return;
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @240,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
    };
    CGImageRef thumbCG = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbCG) return;
    UIImage *thumb = [UIImage imageWithCGImage:thumbCG];
    CGImageRelease(thumbCG);
    [UIImageJPEGRepresentation(thumb, 0.8) writeToFile:thumbPath atomically:YES];
}

- (void)pxWriteThumbnailForImage:(UIImage *)image toPath:(NSString *)path {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return;   // 源文件损坏时 decodedImage 可能为 nil
    CGSize thumbSize = CGSizeMake(120, 120);
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:thumbSize format:format];
    UIImage *thumb = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat scale = MAX(thumbSize.width / image.size.width, thumbSize.height / image.size.height);
        CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
        [image drawInRect:CGRectMake((thumbSize.width - drawSize.width) / 2,
                                     (thumbSize.height - drawSize.height) / 2,
                                     drawSize.width, drawSize.height)];
    }];
    [UIImageJPEGRepresentation(thumb, 0.8) writeToFile:path atomically:YES];
}

#pragma mark - 删/清

- (void)removeItemWithID:(NSString *)historyID completion:(void (^)(void))completion {
    dispatch_async(self.ioQueue, ^{
        [self.storeLock lock];
        [self pxEnsureLoadedLocked];
        NSMutableArray<PXHistoryItem *> *matches = [[NSMutableArray alloc] init];
        for (PXHistoryItem *item in self.items) {
            if ([item.historyID isEqualToString:historyID]) [matches addObject:item];
        }
        for (PXHistoryItem *item in matches) {
            [self.items removeObject:item];
            [self pxDeleteFilesForItem:item];
        }
        NSArray<PXHistoryItem *> *snapshot = [self.items copy];
        [self.storeLock unlock];

        [self pxWriteIndexForItems:snapshot];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

- (void)clearAllWithCompletion:(void (^)(void))completion {
    dispatch_async(self.ioQueue, ^{
        [self.storeLock lock];
        [self pxEnsureLoadedLocked];
        for (PXHistoryItem *item in self.items) {
            [self pxDeleteFilesForItem:item];
        }
        [self.items removeAllObjects];
        [self.storeLock unlock];

        NSString *indexPath = [PXHistoryDirectory() stringByAppendingPathComponent:PXHistoryIndexFileName];
        [[NSFileManager defaultManager] removeItemAtPath:indexPath error:nil];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

#pragma mark - 读

- (NSArray<PXHistoryItem *> *)allItems {
    [self.storeLock lock];
    [self pxEnsureLoadedLocked];
    NSArray<PXHistoryItem *> *snapshot = [self.items copy];
    [self.storeLock unlock];
    return snapshot;
}

- (nullable UIImage *)imageForItem:(PXHistoryItem *)item edited:(BOOL)edited {
    NSString *path = edited ? (item.editedPath ?: item.originalPath) : item.originalPath;
    if (path.length == 0) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

- (void)loadImageForItem:(PXHistoryItem *)item
                  edited:(BOOL)edited
              completion:(void (^)(UIImage *image))completion {
    NSString *primaryPath = edited ? (item.editedPath ?: item.originalPath) : item.originalPath;
    NSString *fallbackPath = item.originalPath;
    dispatch_async(self.ioQueue, ^{
        UIImage *image = [self pxDecodeImageAtPath:primaryPath];
        if (!image && ![primaryPath isEqualToString:fallbackPath]) {
            image = [self pxDecodeImageAtPath:fallbackPath];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
    });
}

/// 读文件并强制像素解码：imageWithContentsOfFile 的解码会推迟到首次绘制（落在主线程），
/// 这里在 IO 队列用 renderer 光栅化，点尺寸/缩放与原加载语义保持一致。
- (nullable UIImage *)pxDecodeImageAtPath:(NSString *)path {
    if (path.length == 0) return nil;
    UIImage *lazyImage = [UIImage imageWithContentsOfFile:path];
    if (!lazyImage || lazyImage.size.width <= 0 || lazyImage.size.height <= 0) return nil;

    @try {
        CGSize pointSize = lazyImage.size;
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        format.scale = lazyImage.scale;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:pointSize format:format];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [lazyImage drawInRect:CGRectMake(0, 0, pointSize.width, pointSize.height)];
        }];
    } @catch (NSException *exception) {
        PXLogError(@"history image decode exception: %@", exception);
        return nil;
    }
}

#pragma mark - IO

- (void)pxDeleteFilesForItem:(PXHistoryItem *)item {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in @[ item.thumbnailPath ?: @"", item.originalPath ?: @"", item.editedPath ?: @"" ]) {
        if (path.length > 0) {
            [fm removeItemAtPath:path error:nil];
        }
    }
}

- (void)pxWriteIndexForItems:(NSArray<PXHistoryItem *> *)items {
    NSMutableArray<NSDictionary *> *array = [[NSMutableArray alloc] init];
    for (PXHistoryItem *item in items) {
        [array addObject:[item dictionaryRepresentation]];
    }
    @try {
        NSData *data = [NSJSONSerialization dataWithJSONObject:array options:0 error:nil];
        if (data) {
            [data writeToFile:[PXHistoryDirectory() stringByAppendingPathComponent:PXHistoryIndexFileName]
                      atomically:YES];
        }
    } @catch (NSException *exception) {
        PXLogError(@"history index write exception: %@", exception);
    }
}

@end
