#import <AppKit/AppKit.h>

/// Returns 1 when the event was handled and must not reach the text system.
extern int LaminaConsumeEvent(void *event);

@interface LaminaApplication : NSApplication
@end

@implementation LaminaApplication

- (void)sendEvent:(NSEvent *)event {
    if (LaminaConsumeEvent((__bridge void *)event)) return;
    [super sendEvent:event];
}

@end
