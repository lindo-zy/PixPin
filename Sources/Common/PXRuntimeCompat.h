#import <Foundation/Foundation.h>

// 版本兼容辅助（仅头文件，避免空 .m）。目标系统为 iOS 16/17（roothide）。

NS_ASSUME_NONNULL_BEGIN

static inline BOOL PXIsAtLeastiOS17(void) {
    if (@available(iOS 17.0, *)) {
        return YES;
    }
    return NO;
}

static inline BOOL PXIsAtLeastiOS16(void) {
    if (@available(iOS 16.0, *)) {
        return YES;
    }
    return NO;
}

NS_ASSUME_NONNULL_END
