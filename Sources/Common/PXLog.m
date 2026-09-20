#import "PXLog.h"

void PXLog(NSString *level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[PixPin][%@] %@", level, message);
}
