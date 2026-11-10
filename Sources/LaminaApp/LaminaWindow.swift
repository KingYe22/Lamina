import AppKit

final class LaminaWindow: NSWindow {
    weak var workspace: Workspace?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let workspace {
            let code = event.keyCode
            if code == VirtualKey.escape || code == VirtualKey.returnKey || code == VirtualKey.tab,
               let field = PanelField.fieldOwningFirstResponder(in: event.window ?? self) {
                field.leave()
                KeyProbe.bump(workspace)
                return
            }
            let routeEscape = event.keyCode == VirtualKey.escape || event.keyCode == PenEscape.keyCode
            if (!KeyRouter.isActivelyEditing(event) || routeEscape),
               KeyRouter.handle(event, workspace: workspace) == nil {
                return
            }
        }
        if event.type == .keyUp, event.keyCode == VirtualKey.space {
            workspace?.active.model.spaceHeld = false
            KeyProbe.bump(workspace)
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let workspace else { return super.performKeyEquivalent(with: event) }
        let routeEscape = event.keyCode == VirtualKey.escape || event.keyCode == PenEscape.keyCode
        if KeyRouter.isActivelyEditing(event), !routeEscape {
            return super.performKeyEquivalent(with: event)
        }
        if KeyRouter.handle(event, workspace: workspace) == nil { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let workspace else {
            super.keyDown(with: event)
            return
        }
        if KeyRouter.handle(event, workspace: workspace) == nil { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        guard let workspace else {
            super.cancelOperation(sender)
            return
        }
        if PenEscapeBridge.perform(workspace: workspace, window: self) { return }
        super.cancelOperation(sender)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelOperation(nil)
            return
        }
        super.doCommand(by: selector)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Screenshot capture asks for the 1033×970 design size. The macos-15
    /// runner's display is about 1024×768, and the default clamp would shrink
    /// the bitmap that check_p0 measures.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if ProcessInfo.processInfo.environment["LAMINA_SHOTS"] != nil {
            return frameRect
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }

    override var isMovableByWindowBackground: Bool {
        get { false }
        set { super.isMovableByWindowBackground = false }
    }
}
