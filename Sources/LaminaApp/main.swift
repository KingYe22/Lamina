import AppKit

@_silgen_name("LaminaApplicationAnchor")
func laminaApplicationAnchor()

laminaApplicationAnchor()
if NSClassFromString("LaminaApplication") == nil {
    fputs("LaminaApplication is not in the ObjC runtime\n", stderr)
}
let app = NSApplication.shared
let name = NSStringFromClass(type(of: app as AnyObject))
if name != "LaminaApplication" {
    let principal = Bundle.main.object(forInfoDictionaryKey: "NSPrincipalClass") ?? "nil"
    fputs("NSApp is \(name) principal=\(principal)\n", stderr)
    exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
