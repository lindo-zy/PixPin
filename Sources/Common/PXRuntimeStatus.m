#import "PXRuntimeStatus.h"
#import "PXConstants.h"
#import "PXLog.h"

@interface PXRuntimeStatus ()
@property (class, readonly, strong) dispatch_queue_t statusQueue;
@end

@implementation PXRuntimeStatus

static dispatch_queue_t _pxStatusQueue = nil;

+ (dispatch_queue_t)statusQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _pxStatusQueue = dispatch_queue_create("com.pixpin.screenshot.status", DISPATCH_QUEUE_SERIAL);
    });
    return _pxStatusQueue;
}

+ (NSString *)statusFilePath {
    return [PXLibraryDataDirectory() stringByAppendingPathComponent:@"status.json"];
}

+ (NSMutableDictionary *)pxCurrentStatusDictionary {
    NSString *path = [self statusFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) {
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([object isKindOfClass:[NSMutableDictionary class]]) return object;
        if ([object isKindOfClass:[NSDictionary class]]) return [object mutableCopy];
    }
    return [[NSMutableDictionary alloc] init];
}

+ (void)pxWriteStatusDictionary:(NSDictionary *)status {
    @try {
        NSData *data = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
        if (data) {
            [data writeToFile:[self statusFilePath] atomically:YES];
        }
    } @catch (NSException *exception) {
        PXLogError(@"status write exception: %@", exception);
    }
}

+ (void)reportLoadedWithCaptureMethod:(NSString *)captureMethod {
    dispatch_async(self.statusQueue, ^{
        NSMutableDictionary *status = [self pxCurrentStatusDictionary];
        status[@"loadedAt"] = @([[NSDate date] timeIntervalSince1970]);
        status[@"captureMethod"] = captureMethod ?: @"none";
        [self pxWriteStatusDictionary:status];
        PXLogInfo(@"status: loaded (capture method %@)", status[@"captureMethod"]);
    });
}

+ (void)reportRequest:(NSString *)modeName outcome:(NSString *)outcome {
    dispatch_async(self.statusQueue, ^{
        NSMutableDictionary *status = [self pxCurrentStatusDictionary];
        status[@"lastRequestAt"] = @([[NSDate date] timeIntervalSince1970]);
        status[@"lastRequestMode"] = modeName ?: @"unknown";
        status[@"lastRequestOutcome"] = outcome ?: @"accepted";
        [self pxWriteStatusDictionary:status];
    });
}

+ (void)reportPhase:(NSString *)phase
                mode:(NSString *)modeName
             message:(NSString *)message {
    dispatch_async(self.statusQueue, ^{
        NSMutableDictionary *status = [self pxCurrentStatusDictionary];
        status[@"lastPhaseAt"] = @([[NSDate date] timeIntervalSince1970]);
        status[@"lastPhase"] = phase ?: @"unknown";
        status[@"lastPhaseMode"] = modeName ?: @"";
        status[@"lastPhaseMessage"] = message ?: @"";
        [self pxWriteStatusDictionary:status];
    });
}

+ (void)reportResultOK:(BOOL)ok
         captureMethod:(NSString *)captureMethod
               message:(NSString *)message {
    dispatch_async(self.statusQueue, ^{
        NSMutableDictionary *status = [self pxCurrentStatusDictionary];
        status[@"lastResultAt"] = @([[NSDate date] timeIntervalSince1970]);
        status[@"lastResult"] = ok ? @"ok" : @"failed";
        if (captureMethod.length > 0) status[@"captureMethod"] = captureMethod;
        status[@"lastResultMessage"] = message ?: @"";
        NSInteger completed = [status[@"completedTasks"] integerValue];
        status[@"completedTasks"] = @(ok ? completed + 1 : completed);
        [self pxWriteStatusDictionary:status];
    });
}

+ (nullable NSDictionary *)readStatus {
    NSString *path = [self statusFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

@end
