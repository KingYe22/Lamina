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

/// Runs at load, before NSApplication.shared, and keeps the class from being dead-stripped.
__attribute__((used, constructor))
static void LaminaApplicationKeep(void) {
    (void)[LaminaApplication class];
}

/// Referenced from main so the linker keeps this class. Nothing else mentions it.
void LaminaApplicationAnchor(void) {
    (void)[LaminaApplication class];
}
