import SwiftUI
import CoreText
import os.log

@main
struct TextCorrectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // 檢查系統版本
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let minimumVersion = (14, 0, 0)
        
        if (osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion) < minimumVersion {
            let alert = NSAlert()
            alert.messageText = "系統版本不相容"
            alert.informativeText = "此應用程式需要 macOS 14.0 (Sonoma) 或更新版本才能運行。"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "確定")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
        
        // 載入自定義字體
        loadCustomFonts()
    }
    
    var body: some Scene {
        // ... existing code ...
    }
    
    private func loadCustomFonts() {
        let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "FontLoader")
        
        // 獲取應用程式Bundle中的字體檔案路徑
        guard let fontURL = Bundle.main.url(forResource: "粉圓體", withExtension: "otf") else {
            logger.error("無法找到粉圓體字體檔案")
            return
        }
        
        // 註冊字體
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) else {
            logger.error("註冊字體失敗：\(error?.takeRetainedValue().localizedDescription ?? "未知錯誤")")
            return
        }
        
        // 初始化FontManager並驗證字體載入是否成功
        _ = FontManager.shared
        
        // 檢查字體是否成功載入
        let fontName = "jf-openhuninn-2.1"  // 粉圓體的實際字體名稱
        if let _ = NSFont(name: fontName, size: 12) {
            logger.info("粉圓體字體載入成功")
            
            // 可選：在啟動時記錄所有可用字體（僅在調試模式下）
            #if DEBUG
            FontManager.shared.listAllAvailableFonts()
            #endif
        } else {
            logger.error("粉圓體字體載入失敗")
        }
    }
} 