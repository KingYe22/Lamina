#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <unistd.h>

static NSFileHandle *reportHandle;
static BOOL failed = NO;
static NSString *statePath;
static pid_t appPid = 0;

static void note(NSString *text) {
    if ([text hasPrefix:@"FAIL"]) failed = YES;
    NSData *data = [[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    [reportHandle writeData:data];
    [reportHandle synchronizeFile];
    fprintf(stderr, "%s\n", text.UTF8String);
}

static NSString *SourceID(TISInputSourceRef source) {
    if (!source) return nil;
    CFTypeRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    if (!value) return nil;
    return (__bridge NSString *)value;
}

static BOOL selectSource(NSString *wanted, NSMutableString *available) {
    CFArrayRef list = TISCreateInputSourceList(NULL, true);
    if (!list) {
        [available appendString:@"TISCreateInputSourceList returned NULL\n"];
        return NO;
    }
    TISInputSourceRef match = NULL;
    CFIndex count = CFArrayGetCount(list);
    for (CFIndex index = 0; index < count; index++) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, index);
        NSString *identifier = SourceID(source);
        if (!identifier) continue;
        if ([identifier containsString:@"SCIM"] || [identifier containsString:@"ITABC"]
            || [identifier containsString:@"Pinyin"] || [identifier containsString:@"ABC"]
            || [identifier containsString:@"keylayout"] || [identifier containsString:@"inputmethod"]
            || [identifier containsString:@"US"] || [identifier containsString:@"Roman"]) {
            [available appendFormat:@"%@\n", identifier];
        }
        if ([identifier isEqualToString:wanted]) match = source;
    }
    if (!match) {
        CFRelease(list);
        return NO;
    }
    BOOL selected = NO;
    NSString *currentID = @"";
    for (int attempt = 0; attempt < 5; attempt++) {
        TISEnableInputSource(match);
        OSStatus status = TISSelectInputSource(match);
        usleep(200000);
        TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
        currentID = current ? (SourceID(current) ?: @"") : @"";
        if (current) CFRelease(current);
        if (status == noErr && [currentID isEqualToString:wanted]) {
            selected = YES;
            break;
        }
    }
    CFRelease(list);
    if (!selected) {
        [available appendFormat:@"current=%@\n", currentID];
    }
    return selected;
}

static NSDictionary *latestState(void) {
    NSString *text = [NSString stringWithContentsOfFile:statePath encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) return nil;
    NSString *line = nil;
    for (NSString *item in [[text componentsSeparatedByString:@"\n"] reverseObjectEnumerator]) {
        if (item.length > 0) { line = item; break; }
    }
    if (!line) return nil;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *token in [line componentsSeparatedByString:@" "]) {
        NSRange eq = [token rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) continue;
        fields[[token substringToIndex:eq.location]] = [token substringFromIndex:eq.location + 1];
    }
    fields[@"__raw"] = line;
    return fields;
}

static NSDictionary *waitUntil(BOOL (^predicate)(NSDictionary *snap), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSDictionary *snap = nil;
    while ([deadline timeIntervalSinceNow] > 0) {
        snap = latestState();
        if (snap && predicate(snap)) return snap;
        usleep(40000);
    }
    return latestState();
}

static CGPoint parsePoint(NSString *value) {
    NSArray *parts = [value componentsSeparatedByString:@","];
    if (parts.count != 2) return CGPointZero;
    return CGPointMake([parts[0] doubleValue], [parts[1] doubleValue]);
}

static void activateApp(void) {
    NSString *script = [NSString stringWithFormat:
        @"tell application \"System Events\" to set frontmost of the first process whose unix id is %d to true",
        appPid];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = @[@"-e", script];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    [task launch];
    [task waitUntilExit];
}

static void postKey(CGKeyCode code, CGEventFlags flags, BOOL down, BOOL up) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (down) {
        CGEventRef event = CGEventCreateKeyboardEvent(source, code, true);
        CGEventSetFlags(event, flags);
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
        usleep(30000);
    }
    if (up) {
        CGEventRef event = CGEventCreateKeyboardEvent(source, code, false);
        CGEventSetFlags(event, flags);
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
        usleep(30000);
    }
    if (source) CFRelease(source);
}

static void click(CGPoint point) {
    activateApp();
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef move = CGEventCreateMouseEvent(source, kCGEventMouseMoved, point, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, move);
    CFRelease(move);
    usleep(30000);
    CGEventRef down = CGEventCreateMouseEvent(source, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, down);
    CFRelease(down);
    usleep(40000);
    CGEventRef up = CGEventCreateMouseEvent(source, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(up);
    if (source) CFRelease(source);
    usleep(120000);
}

static void drag(CGPoint from, CGPoint to) {
    activateApp();
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef move = CGEventCreateMouseEvent(source, kCGEventMouseMoved, from, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, move);
    CFRelease(move);
    usleep(20000);
    CGEventRef down = CGEventCreateMouseEvent(source, kCGEventLeftMouseDown, from, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, down);
    CFRelease(down);
    usleep(30000);
    CGEventRef moved = CGEventCreateMouseEvent(source, kCGEventLeftMouseDragged, to, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, moved);
    CFRelease(moved);
    usleep(30000);
    CGEventRef up = CGEventCreateMouseEvent(source, kCGEventLeftMouseUp, to, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(up);
    if (source) CFRelease(source);
    usleep(80000);
}

static BOOL expectTool(NSString *name, NSString *tool, CGKeyCode code, CGEventFlags flags) {
    NSDictionary *before = latestState();
    NSString *beforeTool = before[@"tool"] ?: @"";
    NSString *beforeStatus = before[@"status"] ?: @"";
    activateApp();
    postKey(code, flags, YES, YES);
    NSDictionary *snap = waitUntil(^BOOL(NSDictionary *state) {
        if (![state[@"tool"] isEqualToString:tool]) return NO;
        if ([beforeTool isEqualToString:tool]) {
            return ![state[@"status"] isEqualToString:beforeStatus];
        }
        return YES;
    }, 2.5);
    BOOL ok = [snap[@"tool"] isEqualToString:tool];
    if ([beforeTool isEqualToString:tool]) {
        ok = ok && ![snap[@"status"] isEqualToString:beforeStatus];
    }
    note([NSString stringWithFormat:@"%@ %@ tool=%@ responder=%@", ok ? @"PASS" : @"FAIL", name, snap[@"tool"] ?: @"?", snap[@"responder"] ?: @"?"]);
    if (!ok) note([NSString stringWithFormat:@"  raw=%@", snap[@"__raw"] ?: @""]);
    return ok;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 5) {
            fprintf(stderr, "usage: keyposter pinyin|abc pid stateFile reportFile\n");
            return 2;
        }
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        appPid = (pid_t)atoi(argv[2]);
        statePath = [NSString stringWithUTF8String:argv[3]];
        NSString *reportPath = [NSString stringWithUTF8String:argv[4]];
        [[NSFileManager defaultManager] createFileAtPath:reportPath contents:nil attributes:nil];
        reportHandle = [NSFileHandle fileHandleForWritingAtPath:reportPath];
        if (!reportHandle) return 2;

        NSString *wanted = [mode isEqualToString:@"abc"]
            ? @"com.apple.keylayout.ABC"
            : @"com.apple.inputmethod.SCIM.ITABC";
        NSMutableString *available = [NSMutableString string];
        if (!selectSource(wanted, available)) {
            note([NSString stringWithFormat:@"FAIL input source %@ was not selected", wanted]);
            note([NSString stringWithFormat:@"FAIL sources:\n%@", available]);
            note(@"FAIL");
            return 1;
        }
        note([NSString stringWithFormat:@"PASS source %@", wanted]);
        activateApp();

        NSDictionary *home = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"phase"] isEqualToString:@"home"] && parsePoint(state[@"new"]).x > 1;
        }, 8);
        if (![home[@"phase"] isEqualToString:@"home"]) {
            note([NSString stringWithFormat:@"FAIL home raw=%@", home[@"__raw"] ?: @""]);
            note(@"FAIL");
            return 1;
        }
        click(parsePoint(home[@"new"]));
        NSDictionary *dialog = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"phase"] isEqualToString:@"dialog"] && parsePoint(state[@"create"]).x > 1;
        }, 4);
        if (![dialog[@"phase"] isEqualToString:@"dialog"]) {
            note([NSString stringWithFormat:@"FAIL new-document raw=%@", latestState()[@"__raw"] ?: @""]);
            note(@"FAIL");
            return 1;
        }
        note(@"PASS open-new-document");
        click(parsePoint(dialog[@"create"]));
        NSDictionary *editor = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"phase"] isEqualToString:@"editor"]
                && [state[@"responder"] isEqualToString:@"VectorCanvas"]
                && parsePoint(state[@"field"]).x > 1;
        }, 4);
        if (![editor[@"responder"] isEqualToString:@"VectorCanvas"] || ![editor[@"phase"] isEqualToString:@"editor"]) {
            note([NSString stringWithFormat:@"FAIL create-focus raw=%@", latestState()[@"__raw"] ?: @""]);
            note(@"FAIL");
            return 1;
        }
        note(@"PASS create-focus-canvas");

        expectTool(@"V", @"selection", 9, 0);
        expectTool(@"M", @"rectangle", 46, 0);
        expectTool(@"L", @"ellipse", 37, 0);

        NSDictionary *beforeField = latestState();
        click(parsePoint(beforeField[@"field"]));
        NSDictionary *editing = waitUntil(^BOOL(NSDictionary *state) {
            NSString *who = state[@"responder"] ?: @"";
            return [who containsString:@"Text"] || [who containsString:@"PanelField"];
        }, 3);
        NSString *who = editing[@"responder"] ?: @"";
        BOOL fieldOK = [who containsString:@"Text"] || [who containsString:@"PanelField"];
        note([NSString stringWithFormat:@"%@ field-focus responder=%@", fieldOK ? @"PASS" : @"FAIL", who]);
        if (!fieldOK) note([NSString stringWithFormat:@"  raw=%@", editing[@"__raw"] ?: @""]);

        activateApp();
        postKey(53, 0, YES, YES);
        NSDictionary *back = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"responder"] isEqualToString:@"VectorCanvas"];
        }, 3);
        BOOL escOK = [back[@"responder"] isEqualToString:@"VectorCanvas"];
        note([NSString stringWithFormat:@"%@ esc-to-canvas responder=%@", escOK ? @"PASS" : @"FAIL", back[@"responder"] ?: @"?"]);
        if (!escOK) note([NSString stringWithFormat:@"  raw=%@", back[@"__raw"] ?: @""]);
        expectTool(@"M-after-esc", @"rectangle", 46, 0);

        expectTool(@"A", @"directSelection", 0, 0);
        expectTool(@"P", @"pen", 35, 0);
        expectTool(@"B", @"brush", 11, 0);
        expectTool(@"N", @"pencil", 45, 0);
        expectTool(@"T", @"text", 17, 0);
        expectTool(@"M2", @"rectangle", 46, 0);
        expectTool(@"L2", @"ellipse", 37, 0);
        expectTool(@"Shift+E", @"eraser", 14, kCGEventFlagMaskShift);
        expectTool(@"R", @"rotate", 15, 0);
        expectTool(@"O", @"reflect", 31, 0);
        expectTool(@"S", @"scale", 1, 0);
        expectTool(@"E", @"freeTransform", 14, 0);

        double zoomBefore = [latestState()[@"zoom"] doubleValue];
        activateApp();
        postKey(24, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *zoomed = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"zoom"] doubleValue] > zoomBefore + 0.001;
        }, 2.5);
        BOOL zoomIn = [zoomed[@"zoom"] doubleValue] > zoomBefore + 0.001;
        note([NSString stringWithFormat:@"%@ Cmd+plus zoom=%@", zoomIn ? @"PASS" : @"FAIL", zoomed[@"zoom"] ?: @"?"]);
        double zoomMid = [latestState()[@"zoom"] doubleValue];
        postKey(27, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *zoomedOut = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"zoom"] doubleValue] < zoomMid - 0.001;
        }, 2.5);
        BOOL zoomOut = [zoomedOut[@"zoom"] doubleValue] < zoomMid - 0.001;
        note([NSString stringWithFormat:@"%@ Cmd+minus zoom=%@", zoomOut ? @"PASS" : @"FAIL", zoomedOut[@"zoom"] ?: @"?"]);

        activateApp();
        postKey(49, 0, YES, NO);
        NSDictionary *held = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"space"] isEqualToString:@"1"];
        }, 2.5);
        BOOL spaceDown = [held[@"space"] isEqualToString:@"1"];
        note([NSString stringWithFormat:@"%@ space space=%@", spaceDown ? @"PASS" : @"FAIL", held[@"space"] ?: @"?"]);
        NSDictionary *panBefore = latestState();
        drag(parsePoint(panBefore[@"down"]), parsePoint(panBefore[@"drag"]));
        NSDictionary *panned = waitUntil(^BOOL(NSDictionary *state) {
            return state[@"pan"] != nil && ![state[@"pan"] isEqualToString:panBefore[@"pan"]];
        }, 2.5);
        BOOL didPan = panned[@"pan"] != nil && ![panned[@"pan"] isEqualToString:panBefore[@"pan"]];
        note([NSString stringWithFormat:@"%@ space-drag pan=%@", (spaceDown && didPan) ? @"PASS" : @"FAIL", panned[@"pan"] ?: @"?"]);
        postKey(49, 0, NO, YES);
        NSDictionary *released = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"space"] isEqualToString:@"0"];
        }, 2.5);
        BOOL spaceUp = [released[@"space"] isEqualToString:@"0"];
        note([NSString stringWithFormat:@"%@ space-up space=%@", spaceUp ? @"PASS" : @"FAIL", released[@"space"] ?: @"?"]);

        activateApp();
        postKey(45, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *created = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"dialog"] isEqualToString:@"1"];
        }, 2.5);
        BOOL dialogShown = [created[@"dialog"] isEqualToString:@"1"];
        note([NSString stringWithFormat:@"%@ Cmd+N dialog=%@", dialogShown ? @"PASS" : @"FAIL", created[@"dialog"] ?: @"?"]);

        postKey(31, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *opened = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"panel"] isEqualToString:@"open"];
        }, 2.5);
        BOOL openOK = [opened[@"panel"] isEqualToString:@"open"];
        note([NSString stringWithFormat:@"%@ Cmd+O panel=%@", openOK ? @"PASS" : @"FAIL", opened[@"panel"] ?: @"?"]);

        postKey(1, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *saved = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"panel"] isEqualToString:@"save"];
        }, 2.5);
        BOOL saveOK = [saved[@"panel"] isEqualToString:@"save"];
        note([NSString stringWithFormat:@"%@ Cmd+S panel=%@", saveOK ? @"PASS" : @"FAIL", saved[@"panel"] ?: @"?"]);

        expectTool(@"M-draw", @"rectangle", 46, 0);
        NSDictionary *drawFrom = latestState();
        int itemsBefore = [drawFrom[@"items"] intValue];
        drag(parsePoint(drawFrom[@"down"]), parsePoint(drawFrom[@"drag"]));
        NSDictionary *drawn = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"items"] intValue] > itemsBefore;
        }, 2.5);
        int drawnCount = [drawn[@"items"] intValue];
        BOOL drew = drawnCount > itemsBefore;
        note([NSString stringWithFormat:@"%@ draw items=%d", drew ? @"PASS" : @"FAIL", drawnCount]);

        postKey(6, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *undone = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"status"] containsString:@"还原"] && [state[@"items"] intValue] < drawnCount;
        }, 2.5);
        BOOL undoOK = [undone[@"status"] containsString:@"还原"] && [undone[@"items"] intValue] < drawnCount;
        note([NSString stringWithFormat:@"%@ Cmd+Z status=%@ items=%@", undoOK ? @"PASS" : @"FAIL", undone[@"status"] ?: @"?", undone[@"items"] ?: @"?"]);

        expectTool(@"M-draw2", @"rectangle", 46, 0);
        NSDictionary *draw2 = latestState();
        int beforeCopy = [draw2[@"items"] intValue];
        drag(parsePoint(draw2[@"down"]), parsePoint(draw2[@"drag"]));
        NSDictionary *drawn2 = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"items"] intValue] > beforeCopy;
        }, 2.5);
        int copiedFrom = [drawn2[@"items"] intValue];
        postKey(8, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *copied = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"status"] containsString:@"已复制"];
        }, 2.5);
        BOOL copyOK = [copied[@"status"] containsString:@"已复制"];
        note([NSString stringWithFormat:@"%@ Cmd+C status=%@", copyOK ? @"PASS" : @"FAIL", copied[@"status"] ?: @"?"]);
        postKey(9, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *pasted = waitUntil(^BOOL(NSDictionary *state) {
            return [state[@"items"] intValue] > copiedFrom && [state[@"tool"] isEqualToString:@"rectangle"];
        }, 2.5);
        BOOL pasteOK = [pasted[@"items"] intValue] > copiedFrom && [pasted[@"tool"] isEqualToString:@"rectangle"];
        note([NSString stringWithFormat:@"%@ Cmd+V tool=%@ items=%@", pasteOK ? @"PASS" : @"FAIL", pasted[@"tool"] ?: @"?", pasted[@"items"] ?: @"?"]);
        postKey(5, kCGEventFlagMaskCommand, YES, YES);
        NSDictionary *grouped = waitUntil(^BOOL(NSDictionary *state) {
            NSString *status = state[@"status"] ?: @"";
            return [status containsString:@"请选择多个对象"] || [status containsString:@"组"];
        }, 2.5);
        NSString *groupStatus = grouped[@"status"] ?: @"";
        BOOL groupOK = [groupStatus containsString:@"请选择多个对象"] || [groupStatus containsString:@"组"];
        note([NSString stringWithFormat:@"%@ Cmd+G status=%@", groupOK ? @"PASS" : @"FAIL", groupStatus]);

        note(failed ? @"FAIL" : @"OK");
        return failed ? 1 : 0;
    }
}
