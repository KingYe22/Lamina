import AppKit

/// A panel value such as stroke weight or keyboard increment.
/// It stays out of the key loop until the pointer clicks it. Return, Esc, and Tab
/// hand focus straight back to the canvas.
class PanelField: NSTextField, NSTextFieldDelegate {
    var onLeave: (() -> Void)?
    /// Panel chrome draws the gray rounded border. Dialog fields draw their own.
    var usesPanelChrome = true
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
        backgroundColor = Theme.panelField
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
        guard usesPanelChrome else { return }
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
            // The field editor is mid-command. Resign on the next turn, after it returns.
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

    /// The panel field whose field editor is the window's first responder, if any.
    static func fieldOwningFirstResponder(in window: NSWindow?) -> PanelField? {
        guard let responder = window?.firstResponder else { return nil }
        if let field = responder as? PanelField { return field }
        if let text = responder as? NSText {
            if let field = text.delegate as? PanelField { return field }
            if let cell = text.delegate as? NSTextFieldCell, let field = cell.controlView as? PanelField {
                return field
            }
        }
        return nil
    }

    func leave() {
        guard !leaving else { return }
        leaving = true
        commitAndResign()
        onLeave?()
        leaving = false
        // AppKit can put the field editor back after endEditing returns inside a key event.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.fieldIsEditing else { return }
            self.commitAndResign()
        }
    }

    private func commitAndResign() {
        armed = false
        refusesFirstResponder = true
        let host = window
        host?.endEditing(for: self)
        CanvasFocus.restore(in: host)
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
        if window?.firstResponder !== canvas {
            window?.makeFirstResponder(nil)
            window?.makeFirstResponder(canvas)
        }
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
