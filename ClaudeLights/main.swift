import AppKit

// Entry point for the AppKit application.
//
// ClaudeLights is a menu bar (status bar) only application: it has no main
// window and no Dock icon. `LSUIElement = YES` in Info.plist keeps it out of
// the Dock and the app switcher; setting the activation policy to `.accessory`
// here makes the same intent explicit in code.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
