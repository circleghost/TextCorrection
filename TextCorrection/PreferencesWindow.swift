import SwiftUI
import Cocoa

// 簡化的PreferencesWindow類，僅用作轉發到AppKitBridge
class PreferencesWindow: NSWindowController {
    private var isPresented: Binding<Bool>
    
    init(isPresented: Binding<Bool>) {
        self.isPresented = isPresented
        
        // 創建一個空窗口 - 實際上不會使用這個窗口
        let window = NSWindow(
            contentRect: NSRect.zero,
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 重寫showWindow直接使用AppKitBridge
    override func showWindow(_ sender: Any?) {
        // 不調用super.showWindow，而是使用AppKitBridge
        AppKitBridge.shared.showSettingsWindow()
        
        // 直接更新綁定值
        DispatchQueue.main.async {
            self.isPresented.wrappedValue = false
        }
    }
    
    deinit {
        // 不需要做任何清理
    }
}