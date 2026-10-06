#import <UIKit/UIKit.h>
@implementation UIImage {
    CGImageRef _image;
    CGFloat _scale;
}
+ (instancetype)imageWithCGImage:(CGImageRef)image scale:(CGFloat)scale orientation:(UIImageOrientation)orientation {
    if (!image) return nil;
    UIImage *result = [[self alloc] init];
    result->_image = CGImageRetain(image);
    result->_scale = scale > 0 ? scale : 1;
    return result;
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
