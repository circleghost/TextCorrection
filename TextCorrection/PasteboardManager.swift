import Cocoa

class PasteboardManager {
    weak var appDelegate: AppDelegate?
    private var lastPasteboardChangeCount: Int = 0
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func setupPasteboardObserver() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            DispatchQueue.global(qos: .userInitiated).async {
                if NSPasteboard.general.changeCount != self?.lastPasteboardChangeCount {
                    self?.lastPasteboardChangeCount = NSPasteboard.general.changeCount
                    DispatchQueue.main.async {
                        self?.appDelegate?.showFloatingButton()
                    }
                }
            }
        }
    }
}