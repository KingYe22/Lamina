import AppKit

/// A panel value such as stroke weight or keyboard increment.
/// It stays out of the key loop until the pointer clicks it. Return, Esc, and Tab
/// hand focus straight back to the canvas.
final class PanelField: NSTextField, NSTextFieldDelegate {
    var onLeave: (() -> Void)?
    private var armed = false
    private var leaving = false

    convenience init(text: String) {
        self.init(frame: .zero)
        stringValue = text
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = true
        isSelectable = true
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = Theme.field
        textColor = Theme.text
        font = Theme.ui(12)
        alignment = .center
        focusRingType = .none
        refusesFirstResponder = true
        delegate = self
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        (fieldIsEditing ? Theme.focus : Theme.fieldBorder).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    var fieldIsEditing: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder === self { return true }
        if let text = responder as? NSText, (text.delegate as AnyObject?) === self { return true }
        return false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { armed }

    override func becomeFirstResponder() -> Bool {
        guard armed else { return false }
        refusesFirstResponder = false
        let ok = super.becomeFirstResponder()
        needsDisplay = true
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        armed = true
        refusesFirstResponder = false
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == VirtualKey.returnKey || event.keyCode == VirtualKey.escape || event.keyCode == VirtualKey.tab {
            leave()
            return
        }
        super.keyDown(with: event)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSResponder.insertTab(_:))
            || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            DispatchQueue.main.async { [weak self] in self?.leave() }
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        armed = false
        refusesFirstResponder = true
        needsDisplay = true
    }

    func leave() {
        guard !leaving else { return }
        leaving = true
        armed = false
        refusesFirstResponder = true
        let host = window
        host?.endEditing(for: self)
        CanvasFocus.restore(in: host)
        onLeave?()
        leaving = false
    }

    static func anyArmed(in window: NSWindow?) -> Bool {
        guard let view = window?.contentView else { return false }
        return scanArmed(view)
    }

    static func disarmAll(in window: NSWindow?) {
        guard let view = window?.contentView else { return }
        disarm(view)
    }

    private static func scanArmed(_ view: NSView) -> Bool {
        if let field = view as? PanelField, field.armed { return true }
        for child in view.subviews where scanArmed(child) { return true }
        return false
    }

    private static func disarm(_ view: NSView) {
        if let field = view as? PanelField {
            field.armed = false
            field.refusesFirstResponder = true
        }
        for child in view.subviews { disarm(child) }
    }
}

enum CanvasFocus {
    static func find(in window: NSWindow?) -> VectorCanvas? {
        find(window?.contentView)
    }

    static func restore(in window: NSWindow?) {
        PanelField.disarmAll(in: window)
        window?.endEditing(for: nil)
        guard let canvas = find(in: window), !canvas.isHiddenOrHasHiddenAncestor else { return }
        window?.initialFirstResponder = canvas
        window?.makeFirstResponder(canvas)
        NSTextInputContext.current?.discardMarkedText()
        NSTextInputContext.current?.deactivate()
        KeyProbe.bump(canvas.workspace)
    }

    private static func find(_ view: NSView?) -> VectorCanvas? {
        guard let view else { return nil }
        if let canvas = view as? VectorCanvas { return canvas }
        for child in view.subviews {
            if let found = find(child) { return found }
        }
        return nil
    }
}
