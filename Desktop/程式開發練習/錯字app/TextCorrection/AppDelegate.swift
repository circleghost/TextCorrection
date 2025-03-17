import Cocoa
import SwiftUI
import Combine
import Foundation
import os.log
import HotKey
import Carbon

// 定義一個本地的ClipboardManagerDelegate協議
protocol ClipboardManagerDelegate: AnyObject {
    func clipboardDidChange(text: String)
}

// FloatingButtonView定義
struct FloatingButtonView: View {
    @EnvironmentObject var appStateObserver: AppStateObserver
    
    var body: some View {
        Button(action: {
            AppKitBridge.shared.processClipboardText()
        }) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.blue))
                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// @main  // 移除 @main 屬性，由 TextCorrectionApp 作為主程序入口點
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppDelegate")
    
    // 窗口控制器
    private var textWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var floatingButtonWindowController: NSWindowController?
    
    // 狀態管理
    private var appState: AppState?
    private var appStateObserver: AppStateObserver?
    
    // 管理器
    private var statusItemManager: StatusItemManager?
    private var clipboardManager: PasteboardManager?
    private var hotKeyManager: HotKeyManager?
    
    // 訂閱集合
    private var cancellables = Set<AnyCancellable>()
    
    // 添加用於存儲設置的屬性
    private var isClipboardMonitoringEnabled: Bool = false
    private var correctionHotkey: String = "⌘+⇧+C"
    private var isHotkeyActive: Bool = true
    
    // MARK: - 應用程序生命週期
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("應用程序已啟動")
        
        // 從UserDefaults加載設置
        loadSettings()
        
        // 初始化AppState和AppStateObserver
        Task { @MainActor in
            self.appState = AppState.shared
            self.appStateObserver = AppStateObserver(appState: AppState.shared)
            
            // 初始化管理器
            statusItemManager = StatusItemManager(appDelegate: self)
            hotKeyManager = HotKeyManager.shared
            
            // 初始化剪貼板管理器
            clipboardManager = PasteboardManager(appDelegate: self)
            clipboardManager?.delegate = self
            
            // 啟動狀態訂閱
            setupStateSubscriptions()
            
            // 設置剪貼板監控
            updateClipboardMonitoring()
            
            // 設置熱鍵
            updateHotkey()
            
            // 設置訂閱
            setupSubscriptions()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("應用程序即將終止")
        
        // 清理資源
        cancellables.forEach { $0.cancel() }
        hotKeyManager?.updateHotkeySettings(enabled: false)
        clipboardManager?.stopMonitoring()
    }
    
    // MARK: - 初始化方法
    
    // 設置AppKitBridge
    private func setupAppKitBridge() {
        // 已經通過TextCorrectionApp設置
        // AppKitBridge.shared.setAppDelegate(self)
    }
    
    // 設置狀態欄圖標
    private func setupStatusItem() {
        // 已在applicationDidFinishLaunching中初始化
        // statusItemManager = StatusItemManager(appDelegate: self)
    }
    
    // 設置剪貼板監控
    private func setupClipboardMonitoring() {
        // 已在applicationDidFinishLaunching中處理
        // clipboardManager = ClipboardManager(delegate: self)
        
        // 根據設置決定是否啟動監控
        // if appStateObserver?.isClipboardMonitoringEnabled == true {
        //     clipboardManager?.startMonitoring()
        // }
    }
    
    // 設置熱鍵
    private func setupHotKeys() {
        // 已在applicationDidFinishLaunching中初始化
        // hotKeyManager = HotKeyManager(appDelegate: self)
        
        // 根據設置註冊熱鍵
        // if appStateObserver?.isHotkeyActive == true {
        //     registerCorrectionHotKey()
        // }
    }
    
    private func validateAPIKey() {
        logger.info("驗證API密鑰")
        
        let apiKey = appStateObserver?.apiKey ?? ""
        
        if !apiKey.isEmpty {
            // 驗證API密鑰有效性
            Task {
                do {
                    // 創建OpenAIService實例
                    let openAIService = OpenAIService()
                    
                    // 使用閉包驗證API密鑰
                    openAIService.validateAPIKey(apiKey) { isValid in
                        Task { @MainActor in
                            // 直接設置屬性而不是調用不存在的方法
                            self.appState?.isApiKeyValid = isValid
                        }
                    }
                } catch {
                    logger.error("驗證API密鑰時出錯: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setupSubscriptions() {
        logger.info("設置訂閱")
        
        // 訂閱剪貼板監控設置變化
        appStateObserver?.$isClipboardMonitoringEnabled
            .sink { [weak self] (isEnabled: Bool) in
                if isEnabled {
                    self?.clipboardManager?.startMonitoring()
                } else {
                    self?.clipboardManager?.stopMonitoring()
                }
            }
            .store(in: &cancellables)
        
        // 訂閱熱鍵設置變化
        appStateObserver?.$isHotkeyActive
            .sink { [weak self] (isEnabled: Bool) in
                if isEnabled {
                    self?.registerCorrectionHotKey()
                } else {
                    // 使用updateHotkeySettings方法替代不存在的unregisterAllHotKeys
                    self?.hotKeyManager?.updateHotkeySettings(enabled: false)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupStateSubscriptions() {
        logger.info("設置AppState訂閱")
        
        // 確保appState和appStateObserver都已初始化
        guard let appState = self.appState,
              let appStateObserver = self.appStateObserver else {
            logger.warning("AppState或AppStateObserver未初始化")
            return
        }
        
        // 訂閱視窗狀態
        Task { @MainActor in
            appState.$windowStates
                .receive(on: RunLoop.main)
                .sink { [weak self] windowStates in
                    guard let self = self else { return }
                    
                    Task { @MainActor in
                        // 更新視窗狀態
                        if windowStates["text"] == true && self.textWindowController == nil {
                            self.showTextWindow()
                        } else if windowStates["text"] == false && self.textWindowController != nil {
                            self.hideTextWindow()
                        }
                        
                        if windowStates["settings"] == true && self.settingsWindowController == nil {
                            self.showSettings()
                        } else if windowStates["settings"] == false && self.settingsWindowController != nil {
                            self.hideSettingsWindow()
                        }
                        
                        if windowStates["floatingButton"] == true && self.floatingButtonWindowController == nil {
                            self.showFloatingButton()
                        } else if windowStates["floatingButton"] == false && self.floatingButtonWindowController != nil {
                            self.hideFloatingButton()
                        }
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - 熱鍵方法
    
    private func registerCorrectionHotKey() {
        logger.info("註冊文本校正熱鍵")
        
        // 從設置中獲取熱鍵信息
        let hotkeyString = appStateObserver?.correctionHotkeyString ?? "⌘+⇧+C"
        
        // 如果沒有設置熱鍵，使用默認值
        if hotkeyString.isEmpty {
            // 使用默認熱鍵
            hotKeyManager?.updateHotkeySettings(enabled: true, hotkeyString: "⌘+⇧+C")
        } else {
            // 使用配置的熱鍵
            hotKeyManager?.updateHotkeySettings(enabled: true, hotkeyString: hotkeyString)
        }
    }
    
    private func handleCorrectionHotKeyPressed() {
        logger.info("熱鍵觸發：文本校正")
        
        // 處理剪貼板文本
        Task { @MainActor in
            AppKitBridge.shared.processClipboardText()
        }
    }
    
    // MARK: - 窗口管理方法
    
    func showTextWindow() {
        logger.info("顯示文本窗口")
        
        if textWindowController == nil {
            // 創建SwiftUI視圖
            let contentView = TextCorrectionView()
                .environmentObject(appStateObserver!)
            
            // 創建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "文本校正"
            window.center()
            window.setFrameAutosaveName("TextCorrectionWindow")
            window.contentView = NSHostingView(rootView: contentView)
            window.delegate = self
            
            // 創建窗口控制器
            textWindowController = NSWindowController(window: window)
        }
        
        textWindowController?.showWindow(nil)
        textWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideTextWindow() {
        logger.info("隱藏文本窗口")
        
        textWindowController?.window?.close()
    }
    
    func showSettings() {
        logger.info("顯示設置窗口")
        
        if settingsWindowController == nil {
            // 創建SwiftUI視圖
            let contentView = SettingsView()
                .environmentObject(appStateObserver!)
            
            // 創建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "設置"
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.contentView = NSHostingView(rootView: contentView)
            window.delegate = self
            
            // 創建窗口控制器
            settingsWindowController = NSWindowController(window: window)
        }
        
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideSettingsWindow() {
        logger.info("隱藏設置窗口")
        
        settingsWindowController?.window?.close()
    }
    
    func showFloatingButton() {
        logger.info("顯示浮動按鈕")
        
        if floatingButtonWindowController == nil {
            // 創建SwiftUI視圖
            let contentView = FloatingButtonView()
                .environmentObject(appStateObserver!)
            
            // 創建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: contentView)
            
            // 設置窗口位置（右下角）
            if let screenFrame = NSScreen.main?.visibleFrame {
                let windowFrame = NSRect(
                    x: screenFrame.maxX - 80,
                    y: screenFrame.minY + 80,
                    width: 60,
                    height: 60
                )
                window.setFrame(windowFrame, display: true)
            }
            
            // 創建窗口控制器
            floatingButtonWindowController = NSWindowController(window: window)
        }
        
        floatingButtonWindowController?.showWindow(nil)
    }
    
    func hideFloatingButton() {
        logger.info("隱藏浮動按鈕")
        
        floatingButtonWindowController?.window?.close()
    }
    
    // MARK: - 文本處理方法
    
    func processTextWithOpenAI(text: String) async {
        logger.info("處理文本，長度: \(text.count)字符")
        
        // 更新處理狀態
        await appState?.updateProcessingStatus(true)
        
        // 獲取API密鑰
        let apiKey = appStateObserver?.apiKey ?? ""
        
        // 確保API密鑰有效
        guard !apiKey.isEmpty else {
            logger.error("API密鑰為空")
            await appState?.updateProcessingStatus(false)
            await appState?.addNotification(type: .error, message: "API密鑰未設置")
            return
        }
        
        // 記錄開始時間
        let startTime = Date()
        
        do {
            // 模擬文本校正結果（實際應用中這裡應該調用OpenAI API）
            // 在真實項目中應該使用 OpenAIService 的實例方法處理
            let openAIService = OpenAIService()
            
            // 模擬可能的錯誤情況
            if Bool.random() && false { // 為了避免實際拋出錯誤，將條件設為false
                throw NSError(domain: "OpenAIServiceError", code: 1001, userInfo: [NSLocalizedDescriptionKey: "模擬的API錯誤"])
            }
            
            // 暫時使用模擬數據，實際項目中應該調用API
            let result = text.capitalized
            
            // 計算處理時間
            let processingTime = Date().timeIntervalSince(startTime)
            
            // 更新文本信息
            await appState?.updateTextInfo(originalText: text, correctedText: result)
            
            // 更新統計信息
            await appState?.updateTextStats(
                originalCharCount: text.count,
                correctedCharCount: result.count,
                processingTime: processingTime
            )
            
            // 添加成功通知
            await appState?.addNotification(
                type: .success,
                message: "文本校正完成，用時 \(String(format: "%.2f", processingTime)) 秒"
            )
            
            // 顯示文本窗口
            await MainActor.run {
                showTextWindow()
            }
        } catch {
            logger.error("處理文本時出錯: \(error.localizedDescription)")
            
            // 添加錯誤通知
            await appState?.addNotification(
                type: .error,
                message: "處理失敗: \(error.localizedDescription)"
            )
        }
        
        // 更新處理狀態
        await appState?.updateProcessingStatus(false)
    }
    
    // 直接處理熱鍵選擇的文本
    func directlyProcessHotkeySelection(_ text: String) {
        Task {
            await processTextWithOpenAI(text: text)
        }
    }
    
    // MARK: - 狀態欄菜單方法
    
    func statusItemClicked() {
        logger.info("狀態欄圖標被點擊")
        
        // 如果文本窗口已打開，則關閉；否則打開設置窗口
        Task { @MainActor in
            if appState?.windowStates["text"] == true {
                hideTextWindow()
            } else {
                showSettings()
            }
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        isClipboardMonitoringEnabled = defaults.bool(forKey: "isClipboardMonitoringEnabled")
        correctionHotkey = defaults.string(forKey: "correctionHotkey") ?? "⌘+⇧+C"
        isHotkeyActive = defaults.bool(forKey: "isHotkeyActive")
        
        logger.info("已加載設置: 剪貼板監控=\(self.isClipboardMonitoringEnabled), 熱鍵=\(self.correctionHotkey), 熱鍵啟用=\(self.isHotkeyActive)")
    }
    
    private func updateClipboardMonitoring() {
        if isClipboardMonitoringEnabled {
            clipboardManager?.startMonitoring()
            logger.info("已啟動剪貼板監控")
        } else {
            clipboardManager?.stopMonitoring()
            logger.info("已停止剪貼板監控")
        }
    }
    
    private func updateHotkey() {
        if isHotkeyActive {
            hotKeyManager?.updateHotkeySettings(enabled: true, hotkeyString: correctionHotkey)
            logger.info("已註冊熱鍵: \(self.correctionHotkey)")
        } else {
            hotKeyManager?.updateHotkeySettings(enabled: false)
            logger.info("已取消註冊熱鍵")
        }
    }
    
    private func showTextCorrectionView() {
        logger.info("顯示文本校正視圖")
        
        // 創建一個新窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "文本校正"
        
        // 創建文本校正視圖
        let textCorrectionView = TextCorrectionView()
            .environmentObject(appStateObserver!)
        
        // 設置窗口的內容視圖
        window.contentView = NSHostingView(rootView: textCorrectionView)
        
        // 顯示窗口並使其成為主窗口
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if window == textWindowController?.window {
            logger.info("文本窗口將要關閉")
            Task { @MainActor in
                appState?.updateWindowState(type: "text", isOpen: false)
            }
        } else if window == settingsWindowController?.window {
            logger.info("設置窗口將要關閉")
            Task { @MainActor in
                appState?.updateWindowState(type: "settings", isOpen: false)
            }
        }
    }
}

// MARK: - ClipboardManagerDelegate

extension AppDelegate: ClipboardManagerDelegate {
    func clipboardDidChange(text: String) {
        logger.info("檢測到剪貼板變化，文本長度: \(text.count)")
        
        // 如果啟用了剪貼板監控，則處理文本
        Task { @MainActor in
            if appStateObserver?.isClipboardMonitoringEnabled == true {
                await processTextWithOpenAI(text: text)
            }
        }
    }
}