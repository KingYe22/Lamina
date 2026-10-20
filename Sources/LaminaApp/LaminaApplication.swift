import AppKit

/// Principal class. `sendEvent` sees the physical key before the text system,
/// so a panel field that is not being edited cannot swallow V / M / L.
@objc(LaminaApplication)
final class LaminaApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        let workspace = (delegate as? AppDelegate)?.keyWorkspace
        if event.type == .keyDown, let workspace, !KeyRouter.isActivelyEditing(event) {
            if KeyRouter.handle(event, workspace: workspace) == nil { return }
        }
        if event.type == .keyUp, event.keyCode == VirtualKey.space {
            if let workspace {
                workspace.active.model.spaceHeld = false
                workspace.active.model.updateLiveModifiers(
                    shift: event.modifierFlags.contains(.shift),
                    option: event.modifierFlags.contains(.option)
                )
                KeyProbe.bump(workspace)
            }
            return
        }
        super.sendEvent(event)
    }
}
