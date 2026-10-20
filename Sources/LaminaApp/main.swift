import AppKit

// Info.plist NSPrincipalClass is LaminaApplication, so this shared instance
// is the subclass whose sendEvent runs before the text input system.
let app = NSApplication.shared
guard app is LaminaApplication else {
    fputs("NSPrincipalClass did not instantiate LaminaApplication\n", stderr)
    exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
