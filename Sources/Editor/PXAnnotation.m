#import "PXAnnotation.h"

static NSString * const PXAnnotationFontName = @"PingFangSC-Semibold";

@interface PXAnnotation ()
@property (nonatomic, copy, readwrite) NSString *annotationID;
@end

@implementation PXAnnotation

+ (NSString *)newAnnotationID {
    return [[NSUUID UUID] UUIDString];
}

- (instancetype)initWithType:(PXAnnotationType)type
                       color:(UIColor *)color
                   lineWidth:(CGFloat)lineWidth
                       alpha:(CGFloat)alpha {
    if (self = [super init]) {
        _annotationID = [PXAnnotation newAnnotationID];
        _type = type;
        _color = color ?: [UIColor redColor];
        _lineWidth = lineWidth > 0 ? lineWidth : 4.0;
        _alpha = (alpha > 0 && alpha <= 1.0) ? alpha : 1.0;
        _points = [[NSMutableArray alloc] init];
        _fontSize = 24.0;
        _zIndex = 0;
    }
    return self;
}

- (CGRect)boundsInImageSpace {
    switch (self.type) {
        case PXAnnotationTypeRectangle:
        case PXAnnotationTypeOval:
        case PXAnnotationTypeMosaic:
            return CGRectInset(self.rect, -self.lineWidth, -self.lineWidth);
        case PXAnnotationTypeText: {
            CGFloat width = fmin(self.rect.size.width > 0 ? self.rect.size.width : 400, 1200);
            CGFloat height = self.fontSize * 1.6;
            return CGRectMake(self.rect.origin.x, self.rect.origin.y, width, height);
        }
        default: {
            if (self.points.count == 0) return CGRectZero;
            CGRect bounds = CGRectNull;
            for (NSValue *value in self.points) {
                CGPoint point = [value CGPointValue];
                CGRect pointRect = CGRectMake(point.x, point.y, 0.001, 0.001);
                bounds = CGRectIsNull(bounds) ? pointRect : CGRectUnion(bounds, pointRect);
            }
            CGFloat pad = self.lineWidth;
            return CGRectInset(bounds, -pad, -pad);
        }
    }
}

- (id)copyWithZone:(NSZone *)zone {
    PXAnnotation *copy = [[PXAnnotation allocWithZone:zone] initWithType:self.type
                                                                   color:self.color
                                                               lineWidth:self.lineWidth
                                                                   alpha:self.alpha];
    // 值拷贝用于撤销/重做的重新加入：必须保留同一 annotationID，
    // 否则 undo(id1)→redo(copy id2)→undo(删 id1) 会在文档里残留 id2。
    copy.annotationID = self.annotationID;
    copy.points = [self.points mutableCopy];
    copy.rect = self.rect;
    copy.text = self.text;
    copy.fontSize = self.fontSize;
    copy.zIndex = self.zIndex;
    return copy;
}

+ (UIFont *)fontForAnnotation:(PXAnnotation *)annotation {
    return [UIFont fontWithName:PXAnnotationFontName size:annotation.fontSize]
        ?: [UIFont boldSystemFontOfSize:annotation.fontSize];
}

@end
