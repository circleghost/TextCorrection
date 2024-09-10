import HotKey

class HotKeyManager {
    weak var appDelegate: AppDelegate?
    var hotKey: HotKey?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func setupHotKey() {
        hotKey = HotKey(key: .space, modifiers: [.control, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            self?.appDelegate?.copyAndRewriteSelectedText()
        }
    }
}