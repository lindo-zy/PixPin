#import "PXTemporaryFileStore.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import "../Capture/PXCaptureProvider.h"

@implementation PXTemporaryFileStore

+ (NSString *)directoryForTaskID:(NSString *)taskID create:(BOOL)create {
    if (taskID.length == 0) {
        return nil;
    }
    NSString *path = [PXTemporaryTasksRoot() stringByAppendingPathComponent:taskID];
    if (create && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return path;
}

+ (NSString *)writeImage:(UIImage *)image
                  taskID:(NSString *)taskID
                    name:(NSString *)name
                   error:(NSError **)error {
    NSString *directory = [self directoryForTaskID:taskID create:YES];
    if (directory.length == 0 || !image) {
        if (error) {
            *error = [NSError errorWithDomain:PXCaptureErrorDomain code:PXCaptureErrorCaptureFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"临时目录或图片无效"}];
        }
        return nil;
    }

    NSString *path = [directory stringByAppendingPathComponent:name];
    // JPEG 0.92 在保持截图可读性的同时控制临时文件体积。
    NSData *data = UIImageJPEGRepresentation(image, 0.92);
    if (!data) {
        data = UIImagePNGRepresentation(image);
    }
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        PXLogError(@"write temp image failed: %@", path);
        return nil;
    }
    return path;
}

+ (void)removeTaskDirectory:(NSString *)taskID {
    if (taskID.length == 0) return;
    NSString *path = [self directoryForTaskID:taskID create:NO];
    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        PXLogInfo(@"temp task dir removed: %@", taskID);
    }
}

+ (void)sweepAllTaskDirectories {
    NSString *root = PXTemporaryTasksRoot();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:root error:nil];
    for (NSString *entry in entries) {
        [fm removeItemAtPath:[root stringByAppendingPathComponent:entry] error:nil];
    }
    if (entries.count > 0) {
        PXLogInfo(@"swept %lu stale task dirs", (unsigned long)entries.count);
    }
}

@end
