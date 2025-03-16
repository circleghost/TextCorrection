import Foundation
import SwiftUI
import Combine
import os.log

/// AppStateObserver 作為SwiftUI視圖的數據源，代理AppState actor
@MainActor
class AppStateObserver: ObservableObject {
    // MARK: - 已發布的屬性
    
    // 基本設置
    @Published var isVisualEffectsEnabled: Bool = false
    @Published var isParticleEffectsEnabled: Bool = false
    @Published var isApiKeyValid: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isOpenAIServiceAvailable: Bool = true
    @Published var isMonitoringClipboard: Bool = false
    
    // 文本相關
    @Published var originalText: String = ""
    @Published var correctedText: String = ""
    @Published var changedWordsCount: Int = 0
    @Published var textProcessingTime: TimeInterval = 0
    @Published var originalCharacterCount: Int = 0
    @Published var correctedCharacterCount: Int = 0
    
    // 通知和UI狀態
    @Published var notifications: [AppNotification] = []
    @Published var activeScreen: ActiveScreen = .main
    @Published var lastError: String = ""
    @Published var statusMessage: String = ""
    
    // 熱鍵設置
    @Published var hotkeysEnabled: Bool = false
    @Published var correctionHotkey: String = ""
    
    // 其他設置
    @Published var apiKey: String = ""
    @Published var fontSize: CGFloat = 12.0
    
    // MARK: - 私有屬性
    
    /// 用於監視AppState變化的任務
    private var monitorTask: Task<Void, Never>?
    
    /// 用於被監視的AppState實例
    private let appState: AppState
    
    // MARK: - 初始化與反初始化
    
    /// 初始化一個新的AppStateObserver實例
    /// - Parameter appState: 要觀察的AppState實例
    init(appState: AppState) {
        self.appState = appState
        // 啟動監視AppState變更的任務
        startMonitoring()
    }
    
    deinit {
        // 取消監視任務
        monitorTask?.cancel()
    }
    
    // MARK: - 監視方法
    
    /// 開始監視AppState的變更
    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            guard let self = self else { return }
            // 每50毫秒檢查一次狀態更新
            while !Task.isCancelled {
                await self.updateFromAppState()
                try? await Task.sleep(nanoseconds: 50_000_000) // 50毫秒
            }
        }
    }
    
    /// 從AppState更新所有屬性
    @MainActor
    private func updateFromAppState() async {
        // 基本設置
        self.isVisualEffectsEnabled = await appState.isVisualEffectsEnabled
        self.isParticleEffectsEnabled = await appState.isParticleEffectsEnabled
        self.isApiKeyValid = await appState.isApiKeyValid
        self.isProcessing = await appState.isProcessing
        self.isOpenAIServiceAvailable = await appState.isOpenAIServiceAvailable
        self.isMonitoringClipboard = await appState.isMonitoringClipboard
        
        // 文本相關
        self.originalText = await appState.originalText
        self.correctedText = await appState.correctedText
        self.changedWordsCount = await appState.changedWordsCount
        self.textProcessingTime = await appState.textProcessingTime
        self.originalCharacterCount = await appState.originalCharacterCount
        self.correctedCharacterCount = await appState.correctedCharacterCount
        
        // 通知和UI狀態
        self.notifications = await appState.notifications
        self.activeScreen = await appState.activeScreen
        self.lastError = await appState.lastError
        self.statusMessage = await appState.statusMessage
        
        // 熱鍵設置
        self.hotkeysEnabled = await appState.hotkeysEnabled
        self.correctionHotkey = await appState.correctionHotkey
        
        // 其他設置
        self.apiKey = await appState.apiKey
        self.fontSize = await appState.fontSize
    }
    
    // MARK: - 操作方法
    
    /// 更新視覺效果設置
    func updateVisualEffects(_ enabled: Bool) {
        Task {
            await appState.updateVisualEffects(enabled)
        }
    }
    
    /// 更新粒子效果設置
    func updateParticleEffects(_ enabled: Bool) {
        Task {
            await appState.updateParticleEffects(enabled)
        }
    }
    
    /// 更新API密鑰
    func updateApiKey(_ key: String) {
        Task {
            await appState.updateApiKey(key)
        }
    }
    
    /// 更新熱鍵設置
    func updateHotkeySettings(enabled: Bool, hotkey: String = "") {
        Task {
            await appState.updateHotkeySettings(enabled: enabled, hotkey: hotkey)
        }
    }
    
    /// 更新剪貼板監控設置
    func updateClipboardMonitoring(_ enabled: Bool) {
        Task {
            await appState.updateClipboardMonitoring(enabled)
        }
    }
    
    /// 更新字體大小
    func updateFontSize(_ size: CGFloat) {
        Task {
            await appState.updateFontSize(size)
        }
    }
    
    /// 更新處理狀態
    func updateProcessingStatus(_ isProcessing: Bool) {
        Task {
            await appState.updateProcessingStatus(isProcessing)
        }
    }
    
    /// 更新OpenAI服務可用性
    func updateOpenAIServiceAvailability(_ isAvailable: Bool) {
        Task {
            await appState.updateOpenAIServiceAvailability(isAvailable)
        }
    }
    
    /// 更新錯誤訊息
    func updateErrorMessage(_ message: String) {
        Task {
            await appState.updateErrorMessage(message)
        }
    }
    
    /// 更新狀態訊息
    func updateStatusMessage(_ message: String) {
        Task {
            await appState.updateStatusMessage(message)
        }
    }
    
    /// 設置活動螢幕
    func setActiveScreen(_ screen: ActiveScreen) {
        Task {
            await appState.setActiveScreen(screen)
        }
    }
    
    /// 更新文本信息
    func updateTextInfo(originalText: String, correctedText: String) {
        Task {
            await appState.updateTextInfo(originalText: originalText, correctedText: correctedText)
        }
    }
    
    /// 更新文本統計信息
    func updateTextStats(originalCharCount: Int, correctedCharCount: Int, processingTime: TimeInterval) {
        Task {
            await appState.updateTextStats(originalCharCount: originalCharCount, 
                                         correctedCharCount: correctedCharCount, 
                                         processingTime: processingTime)
        }
    }
    
    /// 添加通知
    func addNotification(type: NotificationType, message: String) {
        Task {
            await appState.addNotification(type: type, message: message)
        }
    }
    
    /// 移除通知
    func removeNotification(id: UUID) {
        Task {
            await appState.removeNotification(id: id)
        }
    }
    
    /// 清除所有通知
    func clearAllNotifications() {
        Task {
            await appState.clearAllNotifications()
        }
    }
    
    /// 重置設置
    func resetSettings() {
        Task {
            await appState.resetSettings()
        }
    }
    
    /// 重置狀態
    func resetState() {
        Task {
            await appState.resetState()
        }
    }
    
    /// 調試狀態打印
    func printDebugState() {
        Task {
            await appState.printDebugState()
        }
    }
} 