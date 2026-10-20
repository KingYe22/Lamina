#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <stdio.h>

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

static NSApplication *LaminaShared(id self, SEL _cmd) {
    static NSApplication *app;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        app = [[LaminaApplication alloc] init];
    });
    return app;
}

/// Referenced from main so the linker keeps this class. Swift's
/// NSApplication.shared ignores NSPrincipalClass and would otherwise lock in
/// a plain NSApplication before the first event.
void LaminaApplicationAnchor(void) {
    (void)[LaminaApplication class];
    Method method = class_getClassMethod([NSApplication class], @selector(sharedApplication));
    if (method) {
        method_setImplementation(method, (IMP)LaminaShared);
    } else {
        fputs("NSApplication sharedApplication method is missing\n", stderr);
    }
}

NSApplication *LaminaSharedApplication(void) {
    return [NSApplication sharedApplication];
}
