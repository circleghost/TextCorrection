import Foundation
import AppKit

extension NSTextView {
    /// 檢查文本視圖是否已被銷毀（window關閉或視圖已從視圖層次結構中移除）
    var isDestroyed: Bool {
        // 檢查視圖是否已從視圖層次結構中移除
        if superview == nil && window == nil {
            return true
        }
        
        // 檢查視圖的窗口是否已關閉
        if let window = window, !window.isVisible {
            return true
        }
        
        // 檢查視圖是否正在使用無效的內存（嘗試安全訪問一個屬性）
        // 安全地檢查textStorage是否可用
        if let _ = self.textStorage {
            return false
        } else {
            return true
        }
    }
} 