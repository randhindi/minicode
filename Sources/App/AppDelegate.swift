import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let markdownType = UTType("net.daringfireball.markdown")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        offerToBecomeDefault()
    }

    /// Launching without a file (or clicking the Dock icon with no windows) shows the Open panel.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        DispatchQueue.main.async { NSDocumentController.shared.openDocument(nil) }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private var isDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: markdownType)
            .flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
    }

    private func offerToBecomeDefault() {
        let key = "AskedToBecomeDefault"
        guard !UserDefaults.standard.bool(forKey: key), !isDefault else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "Open Markdown files with Markdown Preview?"
        alert.informativeText = "You can change this later from the Markdown Preview menu."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { makeDefault(nil) }
    }

    @objc func makeDefault(_ sender: Any?) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdownType) { error in
            guard let error else { return }
            DispatchQueue.main.async { NSAlert(error: error).runModal() }
        }
    }
}

enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let name = "Markdown Preview"

        main.addSubmenu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Make Default Markdown App", #selector(AppDelegate.makeDefault(_:))),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ])

        let recent = NSMenu(title: "Open Recent")
        recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        recent.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent

        main.addSubmenu("File", [
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recentItem,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save…", #selector(NSDocument.save(_:)), "s"),
            item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]),
            item("Rename…", #selector(NSDocument.rename(_:))),
            item("Move To…", #selector(NSDocument.move(_:))),
            item("Revert To Saved", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("Print…", #selector(NSDocument.printDocument(_:)), "p"),
        ])

        main.addSubmenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)),
            item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue)),
            item("Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: Int(NSFindPanelAction.previous.rawValue)),
            item("Use Selection for Find", #selector(NSTextView.performFindPanelAction(_:)), "e", [.command, .option], tag: Int(NSFindPanelAction.setFindString.rawValue)),
        ])

        main.addSubmenu("View", [
            item("Show Editor", #selector(DocumentWindowController.toggleEditor(_:)), "e"),
            .separator(),
            item("Actual Size", #selector(DocumentWindowController.resetZoom(_:)), "0"),
            item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+"),
            item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        let window = main.addSubmenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        return main
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.tag = tag
        return item
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        addItem(holder)
        return menu
    }
}
