#import "PXAnnotation.h"

static NSString * const PXAnnotationFontName = @"PingFangSC-Semibold";

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
        _fillStyle = PXAnnotationFillStyleHollow;
        _zoom = 2.5;
        _points = [[NSMutableArray alloc] init];
        _fontSize = 24.0;
        _stampNumber = 1;
        _zIndex = 0;
    }
    return self;
}

- (CGRect)boundsInImageSpace {
    switch (self.type) {
        case PXAnnotationTypeRectangle:
        case PXAnnotationTypeOval:
        case PXAnnotationTypeMosaic:
        case PXAnnotationTypeSpotlight:
        case PXAnnotationTypeMagnifier:
        case PXAnnotationTypeSticker:
        case PXAnnotationTypeStamp: {
            CGFloat pad = (self.type == PXAnnotationTypeMosaic || self.type == PXAnnotationTypeSpotlight)
                ? self.lineWidth : self.lineWidth * 0.5;
            return CGRectInset(self.rect, -pad, -pad);
        }
        case PXAnnotationTypeText: {
            UIFont *font = [PXAnnotation fontForAnnotation:self];
            CGFloat width = self.rect.size.width > 0 ? self.rect.size.width : 200.0;
            CGFloat height = self.rect.size.height;
            if (height <= 0) {
                height = ceil(font.lineHeight) + 4.0;
            }
            return CGRectInset(CGRectMake(self.rect.origin.x, self.rect.origin.y, width, height),
                               -2.0, -2.0);
        }
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow:
        default: {
            if (self.points.count == 0) return CGRectZero;
            CGRect bounds = CGRectNull;
            for (NSValue *value in self.points) {
                CGPoint point = [value CGPointValue];
                CGRect pointRect = CGRectMake(point.x, point.y, 0.001, 0.001);
                bounds = CGRectIsNull(bounds) ? pointRect : CGRectUnion(bounds, pointRect);
            }
            CGFloat pad = MAX(self.lineWidth, (self.type == PXAnnotationTypeHighlight) ? self.lineWidth * 1.5 : 0);
            return CGRectInset(bounds, -pad, -pad);
        }
    }
}

- (BOOL)containsImagePoint:(CGPoint)point slop:(CGFloat)slop {
    switch (self.type) {
        case PXAnnotationTypeRectangle:
        case PXAnnotationTypeOval:
        case PXAnnotationTypeMosaic:
        case PXAnnotationTypeSpotlight:
        case PXAnnotationTypeMagnifier:
        case PXAnnotationTypeSticker:
        case PXAnnotationTypeStamp: {
            CGRect hitRect = CGRectInset(self.boundsInImageSpace, -slop, -slop);
            if (!CGRectContainsPoint(hitRect, point)) return NO;
            if (self.type == PXAnnotationTypeOval || self.type == PXAnnotationTypeMagnifier) {
                // 椭圆归一化判据；外扩 slop 后的环带内均允许命中。
                CGFloat dx = (point.x - CGRectGetMidX(hitRect)) / (hitRect.size.width / 2.0);
                CGFloat dy = (point.y - CGRectGetMidY(hitRect)) / (hitRect.size.height / 2.0);
                return (dx * dx + dy * dy) <= 1.0;
            }
            return YES;
        }
        case PXAnnotationTypeText:
            return CGRectContainsPoint(CGRectInset(self.boundsInImageSpace, -slop, -slop), point);
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow: {
            CGFloat threshold = MAX(self.lineWidth + slop, slop * 2.0);
            CGFloat thresholdSq = threshold * threshold;
            for (NSValue *value in self.points) {
                CGPoint vertex = [value CGPointValue];
                CGFloat dx = point.x - vertex.x;
                CGFloat dy = point.y - vertex.y;
                if (dx * dx + dy * dy <= thresholdSq) return YES;
            }
            for (NSUInteger i = 1; i < self.points.count; i++) {
                if ([self pxSegmentDistanceFrom:[self.points[i - 1] CGPointValue]
                                            to:[self.points[i] CGPointValue]
                                         target:point] <= threshold) {
                    return YES;
                }
            }
            return NO;
        }
        default:
            return NO;
    }
}

- (CGFloat)pxSegmentDistanceFrom:(CGPoint)a to:(CGPoint)b target:(CGPoint)p {
    CGFloat abx = b.x - a.x;
    CGFloat aby = b.y - a.y;
    CGFloat lengthSq = abx * abx + aby * aby;
    CGFloat t = (lengthSq > 0) ? ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSq : 0.0;
    t = MAX(0.0, MIN(1.0, t));
    return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby));
}

- (CGPoint)centerInImageSpace {
    CGRect bounds = [self boundsInImageSpace];
    return CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
}

- (void)translateToCenter:(CGPoint)newCenter {
    CGPoint old = [self centerInImageSpace];
    CGFloat dx = newCenter.x - old.x;
    CGFloat dy = newCenter.y - old.y;
    if (self.points.count > 0) {
        NSMutableArray<NSValue *> *shifted = [[NSMutableArray alloc] init];
        for (NSValue *value in self.points) {
            CGPoint p = [value CGPointValue];
            [shifted addObject:[NSValue valueWithCGPoint:CGPointMake(p.x + dx, p.y + dy)]];
        }
        self.points = shifted;
    }
    self.rect = CGRectOffset(self.rect, dx, dy);
}

- (void)applyScale:(CGFloat)scale {
    if (scale <= 0 || scale == 1.0) return;
    CGPoint center = [self centerInImageSpace];
    switch (self.type) {
        case PXAnnotationTypeText:
            // 字号与外框同步缩放：选中框/命中区/裁剪重映射都以 rect 为准。
            self.fontSize = MAX(8.0, MIN(400.0, self.fontSize * scale));
            self.rect = CGRectMake(center.x + (CGRectGetMinX(self.rect) - center.x) * scale,
                                   center.y + (CGRectGetMinY(self.rect) - center.y) * scale,
                                   self.rect.size.width * scale,
                                   self.rect.size.height * scale);
            break;
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow: {
            NSMutableArray<NSValue *> *scaled = [[NSMutableArray alloc] init];
            for (NSValue *value in self.points) {
                CGPoint p = [value CGPointValue];
                [scaled addObject:[NSValue valueWithCGPoint:
                    CGPointMake(center.x + (p.x - center.x) * scale,
                                center.y + (p.y - center.y) * scale)]];
            }
            self.points = scaled;
            self.lineWidth = MAX(1.0, self.lineWidth * scale);
            break;
        }
        default: {
            CGFloat w = self.rect.size.width * scale;
            CGFloat h = self.rect.size.height * scale;
            self.rect = CGRectMake(center.x - w / 2.0, center.y - h / 2.0, w, h);
            if (self.type == PXAnnotationTypeSticker || self.type == PXAnnotationTypeStamp) {
                self.fontSize = MAX(8.0, MIN(400.0, self.fontSize * scale));
            }
            break;
        }
    }
}

- (void)applyRotation:(CGFloat)angle {
    if (self.type == PXAnnotationTypeSticker) {
        self.rotation += angle;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    PXAnnotation *copy = [[PXAnnotation allocWithZone:zone] initWithType:self.type
                                                                   color:self.color
                                                               lineWidth:self.lineWidth
                                                                   alpha:self.alpha];
    // 值拷贝用于撤销/重做：必须保留同一 annotationID，
    // 否则 undo(id1)→redo(copy id2)→undo(删 id1) 会在文档里残留 id2。
    copy.annotationID = self.annotationID;
    copy.fillStyle = self.fillStyle;
    copy.holeIsEllipse = self.holeIsEllipse;
    copy.rotation = self.rotation;
    copy.zoom = self.zoom;
    copy.points = [self.points mutableCopy];
    copy.rect = self.rect;
    copy.text = self.text;
    copy.stickerText = self.stickerText;
    copy.stampNumber = self.stampNumber;
    copy.fontSize = self.fontSize;
    copy.zIndex = self.zIndex;
    return copy;
}

+ (UIFont *)fontForAnnotation:(PXAnnotation *)annotation {
    return [UIFont fontWithName:PXAnnotationFontName size:annotation.fontSize]
        ?: [UIFont boldSystemFontOfSize:annotation.fontSize];
}

@end
