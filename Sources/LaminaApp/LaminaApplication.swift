import AppKit

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
        if code == VirtualKey.escape || code == VirtualKey.returnKey || code == VirtualKey.tab,
           let field = PanelField.fieldOwningFirstResponder(in: event.window ?? NSApp.keyWindow) {
            field.leave()
            KeyProbe.bump(workspace)
            return 1
        }
        if !KeyRouter.isActivelyEditing(event), KeyRouter.handle(event, workspace: workspace) == nil {
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
