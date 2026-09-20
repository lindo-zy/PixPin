#import <Foundation/Foundation.h>
#import "PXHistoryItem.h"

NS_ASSUME_NONNULL_BEGIN

/// 历史索引存储：items.json + 历史目录内自持的图片文件。
/// 容错要求（DEVELOPMENT.md 5.8）：索引损坏时降级重建，绝不抛出异常导致 SpringBoard 崩溃。
/// 写操作异步执行，调用方无需等待磁盘 IO。
@interface PXHistoryStore : NSObject

+ (instancetype)sharedStore;

/// 新增条目。item.originalPath 指向已存在文件时直接拷贝字节（无二次编码损失）；
/// 否则用 sourceImage 在后台队列编码落盘。completion 主线程回调。
- (void)addItem:(PXHistoryItem *)item
     sourceImage:(nullable UIImage *)sourceImage
      limitCount:(NSInteger)limit
      completion:(nullable void (^)(void))completion;

/// 全部条目，按时间倒序。首次访问时惰性加载。
- (NSArray<PXHistoryItem *> *)allItems;

- (void)removeItemWithID:(NSString *)historyID completion:(nullable void (^)(void))completion;
- (void)clearAllWithCompletion:(nullable void (^)(void))completion;

/// 读取条目的原图（优先 editedPath 与否由调用方决定）。同步 IO，禁止在 SpringBoard 主线程调用。
- (nullable UIImage *)imageForItem:(PXHistoryItem *)item edited:(BOOL)edited;

/// 异步读取条目图片：优先编辑图、读取失败回退原图；后台队列解码（含强制像素解码，
/// 编辑器首帧不再整图解码），主线程回调。回调 image 为 nil 表示两个路径都不可读。
- (void)loadImageForItem:(PXHistoryItem *)item
                  edited:(BOOL)edited
              completion:(void (^)(UIImage *image))completion;

@end

NS_ASSUME_NONNULL_END
