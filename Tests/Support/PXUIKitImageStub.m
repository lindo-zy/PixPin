#import <UIKit/UIKit.h>
@implementation UIImage {
    CGImageRef _image;
    CGFloat _scale;
}
// alloc 系初始化器：mock 的 +1 返回必须来自真正 alloc 的对象（入池对象按 +1 交接会在池排空时过度释放）。
- (instancetype)initWithCGImage:(CGImageRef)image scale:(CGFloat)scale orientation:(UIImageOrientation)orientation {
    if (!image) return nil;
    if (self = [super init]) {
        _image = CGImageRetain(image);
        _scale = scale > 0 ? scale : 1;
    }
    return self;
}
+ (instancetype)imageWithCGImage:(CGImageRef)image scale:(CGFloat)scale orientation:(UIImageOrientation)orientation {
    if (!image) return nil;
    return [[self alloc] initWithCGImage:image scale:scale orientation:orientation];
}
- (void)dealloc { if (_image) CGImageRelease(_image); }
- (CGImageRef)CGImage { return _image; }
- (CGFloat)scale { return _scale; }
- (CGSize)size { return CGSizeMake(CGImageGetWidth(_image) / _scale, CGImageGetHeight(_image) / _scale); }
@end
@implementation UIColor {
    CGColorRef _color;
}
+ (instancetype)blackColor {
    UIColor *result = [[self alloc] init];
    result->_color = CGColorCreateGenericRGB(0, 0, 0, 1);
    return result;
}
- (void)dealloc { if (_color) CGColorRelease(_color); }
- (CGColorRef)CGColor { return _color; }
- (void)setFill {}
@end
