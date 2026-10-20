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
            if !KeyRouter.isActivelyEditing(event), KeyRouter.handle(event, workspace: workspace) == nil {
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
        if KeyRouter.isActivelyEditing(event) {
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override var isMovableByWindowBackground: Bool {
        get { false }
        set { super.isMovableByWindowBackground = false }
    }
}
