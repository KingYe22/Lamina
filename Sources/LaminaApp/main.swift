import AppKit

// Build the subclass directly. NSApplication.shared looks up NSPrincipalClass
// and, when that name is not in the ObjC runtime yet, silently creates a plain
// NSApplication. Assigning NSApp first makes sendEvent the subclass.
if NSApp != nil, !(NSApp is LaminaApplication) {
    let principal = Bundle.main.object(forInfoDictionaryKey: "NSPrincipalClass") ?? "nil"
    let found = NSClassFromString("LaminaApplication") != nil
    fputs("NSApp was \(NSStringFromClass(type(of: NSApp as AnyObject))) principal=\(principal) registered=\(found)\n", stderr)
    exit(1)
}
let app = LaminaApplication()
guard app is LaminaApplication else {
    fputs("LaminaApplication() did not return the subclass\n", stderr)
    exit(1)
}
NSApp = app
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
