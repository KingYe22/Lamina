import AppKit

final class LaminaWindow: NSWindow {
    weak var workspace: Workspace?

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
}
