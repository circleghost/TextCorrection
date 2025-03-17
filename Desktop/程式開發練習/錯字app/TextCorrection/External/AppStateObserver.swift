import Foundation
import SwiftUI
import Combine
import os.log

/// AppStateObserver: 作為SwiftUI視圖的數據源，觀察AppState的變化
class AppStateObserver: ObservableObject {
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppStateObserver")
    
    // MARK: - 已發布的屬性
    
    // 基本設置
    @Published var isVisualEffectsEnabled: Bool = true
    @Published var isParticleEffectsEnabled: Bool = true
    @Published var isApiKeyValid: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isOpenAIServiceAvailable: Bool = true
    @Published var isClipboardMonitoringEnabled: Bool = false
    
    // 文本相關
    @Published var originalText: String = ""
    @Published var correctedText: String = ""
    @Published var changedWordsCount: Int = 0
    @Published var textProcessingTime: TimeInterval = 0
    @Published var originalCharacterCount: Int = 0
    @Published var correctedCharacterCount: Int = 0
    
    // 通知和UI狀態
    @Published var notifications: [AppNotification] = []
    @Published var activeScreen: ActiveScreen = .text
    @Published var lastError: String = ""
    @Published var statusMessage: String = ""
    
    // 熱鍵設置
    @Published var isHotkeyActive: Bool = false
    @Published var correctionHotkeyString: String = ""
    
    // 其他設置
    @Published var apiKey: String = ""
    @Published var fontSize: CGFloat = 14
    
    // 窗口狀態
    @Published var windowStates: [String: Bool] = [
        "text": false,
        "settings": false,
        "floatingButton": false
    ]
    
    // MARK: - 私有屬性
    
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    
    // MARK: - 初始化
    
    init(appState: AppState = AppState.shared) {
        self.appState = appState
        logger.info("初始化AppStateObserver")
        startObservingAppState()
    }
    
    deinit {
        stopObservingAppState()
    }
    
    // MARK: - 觀察方法
    
    /// 開始觀察AppState
    func startObservingAppState() {
        logger.info("開始觀察AppState")
        
        // 立即更新一次
        updateFromAppState()
        
        // 設置定時器定期更新
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateFromAppState()
        }
    }
    
    /// 停止觀察AppState
    func stopObservingAppState() {
        logger.info("停止觀察AppState")
        
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
    }
    
    /// 從AppState更新數據
    @MainActor
    func updateFromAppState() {
        // 基本設置
        isVisualEffectsEnabled = appState.isVisualEffectsEnabled
        isParticleEffectsEnabled = appState.isParticleEffectsEnabled
        isApiKeyValid = appState.isApiKeyValid
        isProcessing = appState.isProcessing
        isOpenAIServiceAvailable = appState.isOpenAIServiceAvailable
        isClipboardMonitoringEnabled = appState.isClipboardMonitoringEnabled
        
        // 文本相關
        originalText = appState.originalText
        correctedText = appState.correctedText
        changedWordsCount = appState.changedWordsCount
        textProcessingTime = appState.textProcessingTime
        originalCharacterCount = appState.originalCharacterCount
        correctedCharacterCount = appState.correctedCharacterCount
        
        // 通知和UI狀態
        notifications = appState.notifications
        activeScreen = appState.activeScreen
        statusMessage = appState.statusMessage
        
        // 熱鍵設置
        isHotkeyActive = appState.isHotkeyActive
        correctionHotkeyString = appState.correctionHotkeyString
        
        // 其他設置
        apiKey = appState.apiKey
        fontSize = appState.fontSize
        
        // 窗口狀態
        windowStates = appState.windowStates
    }
    
    // MARK: - 更新AppState的方法
    
    func updateVisualEffects(enabled: Bool) {
        Task {
            await AppState.shared.updateVisualEffects(enabled: enabled)
        }
    }
    
    func updateParticleEffects(enabled: Bool) {
        Task {
            await AppState.shared.updateParticleEffects(enabled: enabled)
        }
    }
    
    func updateHotkeySettings(enabled: Bool) {
        Task {
            await AppState.shared.updateHotkeySettings(enabled: enabled)
        }
    }
    
    func updateClipboardMonitoring(enabled: Bool) {
        Task {
            await AppState.shared.updateClipboardMonitoring(enabled: enabled)
        }
    }
    
    func updateApiKey(_ key: String) {
        Task {
            await AppState.shared.updateApiKey(key)
        }
    }
    
    func updateFontSize(_ size: CGFloat) {
        Task {
            await AppState.shared.updateFontSize(size)
        }
    }
    
    func resetSettings() {
        Task {
            await AppState.shared.resetSettings()
        }
    }
    
    func clearNotifications() {
        Task {
            await AppState.shared.clearAllNotifications()
        }
    }
    
    func removeNotification(id: UUID) {
        Task {
            await AppState.shared.removeNotification(id: id)
        }
    }
    
    /// 設置活動屏幕
    func setActiveScreen(_ screen: ActiveScreen) {
        AppState.shared.setActiveScreen(screen)
    }
    
    /// 更新窗口狀態
    func updateWindowState(type: String, isOpen: Bool) {
        AppState.shared.updateWindowState(type: type, isOpen: isOpen)
    }
}

// 使用AppState.swift中已定義的類型，不再重複定義
// ActiveScreen, NotificationType, 和 AppNotification 已在 AppState.swift 中定義