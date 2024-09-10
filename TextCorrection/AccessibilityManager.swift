import Cocoa
import ApplicationServices

class AccessibilityManager {
    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
            print("請在系統偏好設置中啟用輔助功能權限")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "需要輔助功能權限"
                alert.informativeText = "請在系統偏好設置中為 TextCorrection 啟用輔助功能權限，以便應用程序能夠正常工作。"
                alert.addButton(withTitle: "打開系統偏好設置")
                alert.addButton(withTitle: "取消")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }
}