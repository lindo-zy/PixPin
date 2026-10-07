#import "PXGeometry.h"
#import <math.h>

BOOL PXCaptureStateCanTransition(PXCaptureState from, PXCaptureState to) {
    switch (from) {
        case PXCaptureStateIdle:
            return to == PXCaptureStatePreparing;
        case PXCaptureStatePreparing:
            return to == PXCaptureStateCapturing || to == PXCaptureStateCancelling || to == PXCaptureStateFailed;
        case PXCaptureStateCapturing:
            return to == PXCaptureStateCaptured || to == PXCaptureStateCancelling || to == PXCaptureStateFailed;
        case PXCaptureStateCaptured:
            return to == PXCaptureStatePresenting || to == PXCaptureStateExporting
                || to == PXCaptureStateCancelling || to == PXCaptureStateFailed;
        case PXCaptureStatePresenting:
            return to == PXCaptureStateEditing || to == PXCaptureStateExporting
                || to == PXCaptureStateCancelling || to == PXCaptureStateFailed;
        case PXCaptureStateEditing:
            return to == PXCaptureStatePresenting || to == PXCaptureStateExporting
                || to == PXCaptureStateCancelling || to == PXCaptureStateFailed;
        case PXCaptureStateExporting:
            return to == PXCaptureStateFinished || to == PXCaptureStatePresenting
                || to == PXCaptureStateCancelling || to == PXCaptureStateFailed;
        case PXCaptureStateCancelling:
            return to == PXCaptureStateCancelled;
        case PXCaptureStateFinished:
        case PXCaptureStateCancelled:
        case PXCaptureStateFailed:
            return NO;
    }
    return NO;
}

BOOL PXCaptureStateIsBusy(PXCaptureState state) {
    switch (state) {
        case PXCaptureStateIdle:
        case PXCaptureStateFinished:
        case PXCaptureStateCancelled:
        case PXCaptureStateFailed:
            return NO;
        default:
            return YES;
    }
}

CGRect PXConvertDisplayRectToPixel(CGRect displayRect, CGSize displayBounds, CGSize pixelSize) {
    if (displayBounds.width <= 0.0 || displayBounds.height <= 0.0
        || pixelSize.width <= 0.0 || pixelSize.height <= 0.0) {
        return CGRectZero;
    }
    CGFloat scaleX = pixelSize.width / displayBounds.width;
    CGFloat scaleY = pixelSize.height / displayBounds.height;

    CGRect result;
    result.origin.x = floor(displayRect.origin.x * scaleX);
    result.origin.y = floor(displayRect.origin.y * scaleY);
    result.size.width = ceil(displayRect.size.width * scaleX);
    result.size.height = ceil(displayRect.size.height * scaleY);

    result = CGRectIntersection(result, CGRectMake(0, 0, pixelSize.width, pixelSize.height));
    if (result.size.width < 1.0 || result.size.height < 1.0) {
        return CGRectZero;
    }
    return result;
}

CGRect PXClampSelectionRect(CGRect rect, CGSize containerSize, CGFloat minimumSize) {
    CGRect container = CGRectMake(0, 0, containerSize.width, containerSize.height);
    rect = CGRectIntersection(rect, container);
    if (CGRectIsNull(rect)) {
        return CGRectZero;
    }

    if (rect.size.width < minimumSize || rect.size.height < minimumSize) {
        // 太小则丢弃，由调用方决定是否重置为默认选区，绝不悄悄产生误触裁剪。
        return CGRectZero;
    }

    CGFloat x = fmin(fmax(rect.origin.x, 0.0), containerSize.width - rect.size.width);
    CGFloat y = fmin(fmax(rect.origin.y, 0.0), containerSize.height - rect.size.height);
    return CGRectMake(x, y, rect.size.width, rect.size.height);
}

CGRect PXConstrainFloatingRect(CGRect frame, CGRect bounds) {
    if (CGRectIsEmpty(frame) || CGRectIsEmpty(bounds) || CGRectIsNull(frame) || CGRectIsNull(bounds) ||
        !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
        !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
        !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height)) return CGRectZero;
    CGFloat otherX = CGRectGetMaxX(bounds) - frame.size.width;
    CGFloat otherY = CGRectGetMaxY(bounds) - frame.size.height;
    frame.origin.x = MAX(MIN(CGRectGetMinX(bounds), otherX), MIN(frame.origin.x, MAX(CGRectGetMinX(bounds), otherX)));
    frame.origin.y = MAX(MIN(CGRectGetMinY(bounds), otherY), MIN(frame.origin.y, MAX(CGRectGetMinY(bounds), otherY)));
    return frame;
}

CGRect PXApplySelectionEdgeSnap(CGRect rect, CGSize containerSize, CGFloat distance) {
    if (!(distance > 0.0) || !isfinite(distance)) return rect;
    if (CGRectIsEmpty(rect) || containerSize.width <= 0.0 || containerSize.height <= 0.0) return rect;
    if (rect.size.width > containerSize.width || rect.size.height > containerSize.height) return rect;
    CGFloat leftGap = rect.origin.x;
    CGFloat rightGap = containerSize.width - CGRectGetMaxX(rect);
    if ((leftGap <= distance || rightGap <= distance) && leftGap <= rightGap) {
        rect.origin.x = 0.0;
    } else if (rightGap <= distance) {
        rect.origin.x = containerSize.width - rect.size.width;
    }
    CGFloat topGap = rect.origin.y;
    CGFloat bottomGap = containerSize.height - CGRectGetMaxY(rect);
    if ((topGap <= distance || bottomGap <= distance) && topGap <= bottomGap) {
        rect.origin.y = 0.0;
    } else if (bottomGap <= distance) {
        rect.origin.y = containerSize.height - rect.size.height;
    }
    return rect;
}

NSString *PXStringFromCaptureMode(PXCaptureMode mode) {
    switch (mode) {
        case PXCaptureModeFull: return @"full";
        case PXCaptureModeArea: return @"area";
        case PXCaptureModeFreeze: return @"freeze";
        case PXCaptureModeMarkup: return @"markup";
        case PXCaptureModeInstant: return @"instant";
        case PXCaptureModeLong: return @"long";
    }
    return @"unknown";
}

NSString *PXStringFromOutputAction(PXOutputAction action) {
    switch (action) {
        case PXOutputActionSave: return @"save";
        case PXOutputActionCopy: return @"copy";
        case PXOutputActionShare: return @"share";
        case PXOutputActionSaveAndCopy: return @"save+copy";
        case PXOutputActionSaveAndDeleteSource: return @"save+delete-source";
        case PXOutputActionPreviewOnly: return @"preview-only";
    }
    return @"unknown";
}

NSString *PXStringFromCaptureState(PXCaptureState state) {
    switch (state) {
        case PXCaptureStateIdle: return @"idle";
        case PXCaptureStatePreparing: return @"preparing";
        case PXCaptureStateCapturing: return @"capturing";
        case PXCaptureStateCaptured: return @"captured";
        case PXCaptureStatePresenting: return @"presenting";
        case PXCaptureStateEditing: return @"editing";
        case PXCaptureStateExporting: return @"exporting";
        case PXCaptureStateFinished: return @"finished";
        case PXCaptureStateCancelling: return @"cancelling";
        case PXCaptureStateCancelled: return @"cancelled";
        case PXCaptureStateFailed: return @"failed";
    }
    return @"unknown";
}
