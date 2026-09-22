#import "PXEditorDocument.h"

@interface PXEditorDocument ()
@property (nonatomic, strong, readwrite) UIImage *sourceImage;
@property (nonatomic, strong) NSMutableArray<PXAnnotation *> *mutableAnnotations;
@property (nonatomic, assign, readwrite) CGRect cropTransform;
@property (nonatomic, assign) NSInteger stampCounter;
@end

@implementation PXEditorDocument

- (instancetype)initWithSourceImage:(UIImage *)sourceImage {
    if (self = [super init]) {
        NSParameterAssert(sourceImage);
        _sourceImage = sourceImage;
        _mutableAnnotations = [[NSMutableArray alloc] init];
        _backgroundColor = [UIColor whiteColor];
        _stampCounter = 0;
    }
    return self;
}

- (NSArray<PXAnnotation *> *)annotations {
    return [self.mutableAnnotations copy];
}

- (void)pxReindex {
    [self.mutableAnnotations enumerateObjectsUsingBlock:^(PXAnnotation *annotation, NSUInteger index, BOOL *stop) {
        annotation.zIndex = index;
    }];
}

- (void)addAnnotation:(PXAnnotation *)annotation {
    if (!annotation) return;
    annotation.zIndex = self.mutableAnnotations.count;
    [self.mutableAnnotations addObject:annotation];
    [self pxReindex];
}

- (void)insertAnnotation:(PXAnnotation *)annotation atIndex:(NSUInteger)index {
    if (!annotation) return;
    NSUInteger clamped = MIN(index, self.mutableAnnotations.count);
    [self.mutableAnnotations insertObject:annotation atIndex:clamped];
    [self pxReindex];
}

- (void)removeAnnotationWithID:(NSString *)annotationID {
    if (annotationID.length == 0) return;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"annotationID == %@", annotationID];
    [self.mutableAnnotations filterUsingPredicate:predicate];
    [self pxReindex];
}

- (nullable PXAnnotation *)annotationWithID:(NSString *)annotationID {
    if (annotationID.length == 0) return nil;
    for (PXAnnotation *annotation in self.mutableAnnotations) {
        if ([annotation.annotationID isEqualToString:annotationID]) {
            return annotation;
        }
    }
    return nil;
}

- (NSUInteger)indexOfAnnotationWithID:(NSString *)annotationID {
    if (annotationID.length == 0) return NSNotFound;
    for (NSUInteger i = 0; i < self.mutableAnnotations.count; i++) {
        if ([self.mutableAnnotations[i].annotationID isEqualToString:annotationID]) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)bringAnnotationToFront:(NSString *)annotationID {
    NSUInteger index = [self indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound || index == self.mutableAnnotations.count - 1) return;
    PXAnnotation *annotation = self.mutableAnnotations[index];
    [self.mutableAnnotations removeObjectAtIndex:index];
    [self.mutableAnnotations addObject:annotation];
    [self pxReindex];
}

- (nullable PXAnnotation *)lastAnnotation {
    return self.mutableAnnotations.lastObject;
}

- (void)replaceContentWithImage:(UIImage *)image annotations:(NSArray<PXAnnotation *> *)annotations {
    NSParameterAssert(image);
    NSParameterAssert(annotations);
    _sourceImage = image;
    _mutableAnnotations = [annotations mutableCopy];
    [self pxReindex];
}

- (NSInteger)nextStampNumber {
    self.stampCounter += 1;
    return self.stampCounter;
}

@end
