import AppKit
import LaminaCore

/// Called from the Objective-C principal class. The subclass itself lives in
/// LaminaApplication.m so NSClassFromString can see it before main().
@_cdecl("LaminaConsumeEvent")
func laminaConsumeEvent(_ eventPointer: UnsafeMutableRawPointer) -> Int32 {
    let event = Unmanaged<NSEvent>.fromOpaque(eventPointer).takeUnretainedValue()
    let workspace = (NSApp.delegate as? AppDelegate)?.keyWorkspace
    if event.type == .keyDown, let workspace {
        // Resign a panel field here, before the field editor or an input method sees Esc.
        // doCommandBy only schedules the resign, and Pinyin can swallow the key first.
        let code = event.keyCode
        if event.modifierFlags.contains(.command), code == VirtualKey.ansiA,
           let field = PanelField.fieldOwningFirstResponder(in: event.window ?? NSApp.keyWindow) {
            field.currentEditor()?.selectAll(nil)
            KeyProbe.bump(workspace)
            return 1
        }
        if code == VirtualKey.escape || code == VirtualKey.returnKey || code == VirtualKey.tab,
           let field = PanelField.fieldOwningFirstResponder(in: event.window ?? NSApp.keyWindow) {
            field.leave()
            KeyProbe.bump(workspace)
            return 1
        }
        // Esc still reaches the router while Pinyin has made a text view first
        // responder. Other keys keep the field-editor path.
        let routeEscape = event.keyCode == VirtualKey.escape || event.keyCode == PenEscape.keyCode
        if (!KeyRouter.isActivelyEditing(event) || routeEscape),
           KeyRouter.handle(event, workspace: workspace) == nil {
            return 1
        }
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
        return 1
    }
    return 0
}

@_cdecl("LaminaCancelOperation")
func laminaCancelOperation() -> Int32 {
    guard let workspace = (NSApp.delegate as? AppDelegate)?.keyWorkspace else { return 0 }
    return PenEscapeBridge.perform(workspace: workspace, window: NSApp.keyWindow) ? 1 : 0
}
