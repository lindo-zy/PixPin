#import "PXExternalRequest.h"
#import "PXConstants.h"

BOOL PXIsExternalURL(NSURL *url) {
    return [url isKindOfClass:NSURL.class] &&
        [url.scheme.lowercaseString isEqualToString:PXExternalURLScheme];
}

NSString *PXNotificationNameForExternalURL(NSURL *url) {
    if (!PXIsExternalURL(url)) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!parts || parts.user != nil || parts.password != nil || parts.port != nil ||
        parts.query != nil || parts.fragment != nil) return nil;

    NSString *host = parts.host.lowercaseString ?: @"";
    NSString *path = parts.percentEncodedPath ?: @"";
    // 不解码路径，避免编码的斜杠、空格等被解释为另一条指令。
    if ((host.length == 0 || [host isEqualToString:@"activate"]) &&
        (path.length == 0 || [path isEqualToString:@"/"])) {
        return (__bridge NSString *)PXDarwinActivate;
    }
    if ([host isEqualToString:@"cancel"] &&
        (path.length == 0 || [path isEqualToString:@"/"])) {
        return (__bridge NSString *)PXDarwinCaptureCancel;
    }
    if (![host isEqualToString:@"capture"]) return nil;

    NSDictionary<NSString *, NSString *> *routes = @{
        @"/full": (__bridge NSString *)PXDarwinCaptureFull,
        @"/area": (__bridge NSString *)PXDarwinCaptureArea,
        @"/freeze": (__bridge NSString *)PXDarwinCaptureFreeze,
        @"/instant": (__bridge NSString *)PXDarwinCaptureInstant,
        @"/markup": (__bridge NSString *)PXDarwinCaptureMarkup,
        @"/cancel": (__bridge NSString *)PXDarwinCaptureCancel,
    };
    return routes[path];
}
