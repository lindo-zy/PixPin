#import "PXURLSchemeCell.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXLog.h"

@implementation PXURLSchemeCell {
    NSInteger _copyFeedbackGeneration;
}

- (NSString *)pxSchemeURL {
    return [NSString stringWithFormat:@"%@://activate", PXExternalURLScheme];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;

    NSString *url = [self pxSchemeURL];
    self.textLabel.text = @"URL Scheme";
    self.detailTextLabel.text = url;
    self.accessibilityLabel = @"URL Scheme，点击复制";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityValue = url;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(pxCopyScheme)];
    [self addGestureRecognizer:tap];
    return self;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    return [self initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil specifier:specifier];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _copyFeedbackGeneration++;
    self.detailTextLabel.text = [self pxSchemeURL];
}

- (void)pxCopyScheme {
    NSString *url = [self pxSchemeURL];
    UIPasteboard.generalPasteboard.string = url;
    PXLogInfo(@"prefs url-scheme copied");

    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];

    _copyFeedbackGeneration++;
    NSInteger generation = _copyFeedbackGeneration;
    self.detailTextLabel.text = @"已复制 ✓";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == self->_copyFeedbackGeneration) {
            self.detailTextLabel.text = url;
        }
    });
}

@end
