import Foundation
import UserNotifications
import os.log

/// 系統通知管理器
class NotificationManager {
    /// 單例實例
    static let shared = NotificationManager()
    
    /// 是否啟用通知功能（默認禁用）
    var isNotificationsEnabled = false
    
    /// 日誌
    private let logger = Logger(subsystem: "com.text.correction", category: "NotificationManager")
    
    /// 通知類型
    enum NotificationType {
        case info
        case success
        case warning
        case error
        
        /// 通知聲音
        var sound: UNNotificationSound {
            switch self {
            case .info:
                return UNNotificationSound.default
            case .success:
                return UNNotificationSound.default
            case .warning:
                return UNNotificationSound.default
            case .error:
                return UNNotificationSound.default
            }
        }
        
        /// 通知標識符前綴
        var identifier: String {
            switch self {
            case .info: return "info"
            case .success: return "success"
            case .warning: return "warning"
            case .error: return "error"
            }
        }
    }
    
    /// 私有初始化方法
    private init() {
        // 請求通知權限（只有在啟用時才真正請求）
        if isNotificationsEnabled {
            requestAuthorization()
        }
    }
    
    /// 請求通知權限
    func requestAuthorization() {
        // 如果通知被禁用，則直接返回
        if !isNotificationsEnabled {
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                self.logger.debug("通知權限已授予")
            } else if let error = error {
                self.logger.error("通知權限請求失敗: \(error.localizedDescription)")
            } else {
                self.logger.warning("通知權限被拒絕")
            }
        }
    }
    
    /// 發送系統通知
    /// - Parameters:
    ///   - title: 通知標題
    ///   - message: 通知內容
    ///   - type: 通知類型
    ///   - delay: 延遲時間（秒）
    func sendNotification(title: String, message: String, type: NotificationType = .info, delay: TimeInterval = 0.1) {
        // 如果通知被禁用，僅記錄日誌但不發送通知
        if !isNotificationsEnabled {
            self.logger.debug("通知已禁用: \(title) - \(message)")
            return
        }
        
        // 創建通知內容
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = type.sound
        content.categoryIdentifier = "TextCorrection"
        
        // 生成唯一標識符
        let identifier = "\(type.identifier)_\(UUID().uuidString)"
        
        // 創建觸發器（延遲後觸發）
        // 確保時間間隔至少為 0.1 秒，避免系統崩潰
        let safeDelay = max(0.1, delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: safeDelay, repeats: false)
        
        // 創建通知請求
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // 添加通知
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("添加通知失敗: \(error.localizedDescription)")
            } else {
                self.logger.debug("成功計劃通知: \(identifier)")
            }
        }
    }
    
    /// 發送文本處理完成通知
    /// - Parameters:
    ///   - originalTextCount: 原始文本字數
    ///   - correctedTextCount: 校正後文本字數
    ///   - wordsChanged: 更改的字詞數量
    func sendCorrectionCompleteNotification(originalTextCount: Int, correctedTextCount: Int, wordsChanged: Int) {
        let title = "文本校正完成"
        let message = "已完成 \(originalTextCount) 字的校正，修改了 \(wordsChanged) 處內容。"
        
        sendNotification(title: title, message: message, type: .success)
    }
    
    /// 發送錯誤通知
    /// - Parameter errorMessage: 錯誤消息
    func sendErrorNotification(errorMessage: String) {
        let title = "處理錯誤"
        sendNotification(title: title, message: errorMessage, type: .error)
    }
    
    /// 發送剪貼板文本檢測通知
    /// - Parameter textLength: 檢測到的文本長度
    func sendClipboardDetectedNotification(textLength: Int) {
        let title = "檢測到剪貼板文本"
        let message = "檢測到 \(textLength) 字的文本已複製到剪貼板，點擊通知進行校正。"
        
        sendNotification(title: title, message: message, type: .info)
    }
    
    /// 清除所有通知
    func clearAllNotifications() {
        // 如果通知被禁用，直接返回
        if !isNotificationsEnabled {
            return
        }
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        logger.debug("已清除所有通知")
    }
} 