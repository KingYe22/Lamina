#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
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

/// Selected input source as seen by this process. Prefers 简体拼音 when that mode is selected.
const char *LaminaCurrentInputSource(void) {
    static char buffer[512];
    buffer[0] = 0;
    NSString *best = nil;
    const void *keys[] = { kTISPropertyInputSourceIsSelected };
    const void *values[] = { kCFBooleanTrue };
    CFDictionaryRef filter = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef list = filter ? TISCreateInputSourceList(filter, false) : NULL;
    if (filter) CFRelease(filter);
    if (list) {
        CFIndex count = CFArrayGetCount(list);
        for (CFIndex index = 0; index < count; index++) {
            TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, index);
            CFTypeRef ident = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
            if (!ident) continue;
            NSString *value = (__bridge NSString *)ident;
            if ([value isEqualToString:@"com.apple.inputmethod.SCIM.ITABC"]) {
                best = value;
                break;
            }
            if (!best) best = value;
        }
        CFRelease(list);
    }
    if (!best) {
        TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
        if (current) {
            CFTypeRef ident = TISGetInputSourceProperty(current, kTISPropertyInputSourceID);
            if (ident) best = (__bridge NSString *)ident;
            CFRelease(current);
        }
    }
    if (best) {
        [best getCString:buffer maxLength:sizeof(buffer) encoding:NSUTF8StringEncoding];
    }
    return buffer;
}
