import Cocoa

class StatusItemManager {
    weak var appDelegate: AppDelegate?
    var statusItem: NSStatusItem?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "文字校正")
            button.action = #selector(appDelegate?.statusItemClicked)
            button.target = appDelegate
        }
    }
}