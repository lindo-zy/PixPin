#import "PXEditorDocument.h"

@interface PXEditorDocument ()
@property (nonatomic, strong, readwrite) UIImage *sourceImage;
@property (nonatomic, strong) NSMutableArray<PXAnnotation *> *mutableAnnotations;
@property (nonatomic, assign, readwrite) CGRect cropTransform;
@end

@implementation PXEditorDocument

- (instancetype)initWithSourceImage:(UIImage *)sourceImage {
    if (self = [super init]) {
        NSParameterAssert(sourceImage);
        _sourceImage = sourceImage;
        _mutableAnnotations = [[NSMutableArray alloc] init];
        _backgroundColor = [UIColor whiteColor];
    }
    return self;
}

- (NSArray<PXAnnotation *> *)annotations {
    return [self.mutableAnnotations copy];
}

- (void)addAnnotation:(PXAnnotation *)annotation {
    if (!annotation) return;
    annotation.zIndex = self.mutableAnnotations.count;
    [self.mutableAnnotations addObject:annotation];
}

- (void)removeAnnotationWithID:(NSString *)annotationID {
    if (annotationID.length == 0) return;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"annotationID == %@", annotationID];
    [self.mutableAnnotations filterUsingPredicate:predicate];
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

- (nullable PXAnnotation *)lastAnnotation {
    return self.mutableAnnotations.lastObject;
}

@end
