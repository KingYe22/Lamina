import AppKit

// Touch the subclass so it is registered before NSApplication.shared reads
// NSPrincipalClass. Allocating it here makes run() try to create a second one.
private let registerLaminaApplication: AnyClass = LaminaApplication.self

_ = registerLaminaApplication
let app = NSApplication.shared
if !(app is LaminaApplication) {
    let principal = Bundle.main.object(forInfoDictionaryKey: "NSPrincipalClass") ?? "nil"
    fputs("NSApp is \(NSStringFromClass(type(of: app as AnyObject))) principal=\(principal)\n", stderr)
    exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
