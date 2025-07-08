import Cocoa
import ApplicationServices
import os.log

/// 輔助功能和權限管理器
@MainActor
class AccessibilityManager {
    // 日誌對象
    private static let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AccessibilityManager")
    
    // 單例
    static let shared = AccessibilityManager()
    
    // 權限狀態
    private(set) var isAccessibilityEnabled = false
    private(set) var isAppleEventsAuthorized = false
    
    // 檢查輔助功能權限狀態
    func checkAccessibilityPermissions() {
        Self.logger.debug("檢查輔助功能權限")
        
        // 檢查輔助功能API權限（不顯示提示）
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: false]
        isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if isAccessibilityEnabled {
            Self.logger.info("輔助功能權限已授予")
        } else {
            Self.logger.notice("未獲得輔助功能權限")
        }
        
        // 檢查Apple Events權限
        checkAppleEventsAuthorization()
    }
    
    // 檢查Apple Events權限
    private func checkAppleEventsAuthorization() {
        // 因為Apple Events沒有專門的檢測方法，我們可以通過嘗試執行一個簡單的腳本來檢測
        let script = """
        tell application "System Events"
            return name of first process
        end tell
        """
        
        var error: NSDictionary?
        if let _ = NSAppleScript(source: script)?.executeAndReturnError(&error) {
            isAppleEventsAuthorized = true
            Self.logger.info("Apple Events權限已授予")
        } else {
            isAppleEventsAuthorized = false
            Self.logger.notice("未獲得Apple Events權限: \(error?.description ?? "未知錯誤")")
        }
    }
    
    // 請求所有必要的權限
    @MainActor
    func requestAllPermissions() {
        Self.logger.debug("請求所有必要的權限")
        
        // 首先請求輔助功能權限
        requestAccessibilityPermission()
    }
    
    // 請求輔助功能權限
    @MainActor
    func requestAccessibilityPermission() {
        Self.logger.debug("請求輔助功能權限")
        
        // 設置選項，顯示提示
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
            Self.logger.notice("彈出輔助功能權限請求對話框")
            
            // 創建一個更友好的對話框，提供說明和引導
            let alert = NSAlert()
            alert.messageText = "需要輔助功能權限"
            alert.informativeText = """
            錯字App需要輔助功能權限才能正常工作。這些權限使應用程式能夠:
            
            • 檢測您選擇的文本
            • 處理熱鍵操作
            • 將校正結果直接插入到您的文檔中
            
            請在接下來的系統對話框中點擊"允許"，然後在系統偏好設置中勾選錯字App。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打開系統偏好設置")
            alert.addButton(withTitle: "以後再說")
            
            // 顯示自定義圖標
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                alert.icon = appIcon
            }
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 打開系統偏好設置的輔助功能面板
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        } else {
            // 權限已授予
            Self.logger.info("輔助功能權限已獲取")
            isAccessibilityEnabled = true
        }
    }
    
    // 在啟動時檢查權限並顯示狀態
    @MainActor
    static func checkPermissionsOnLaunch() {
        // 檢查當前權限狀態
        shared.checkAccessibilityPermissions()
        
        // 如果尚未授予必要權限，顯示警告
        if !shared.isAccessibilityEnabled {
            logger.notice("啟動時未獲得輔助功能權限，顯示提示")
            
            // 延遲顯示權限請求，以避免在啟動時立即彈出對話框
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                shared.requestAccessibilityPermission()
            }
        }
    }
}