import Cocoa
import SwiftUI
import Carbon
import HotKey
import KeychainAccess
import os.log
import Combine

// 確保在整個檔案都可以使用 AppState 和 AppStateObserver
import Foundation

// 新增非 actor 隔離的工具函數用於獲取 API 金鑰
@Sendable
func getOpenAIApiKey() -> String {
    do {
        let keychain = Keychain(service: "com.yourcompany.TextCorrection")
        return try keychain.get("OpenAIApiKey") ?? ""
    } catch {
        print("無法取得 API 金鑰")
        return ""
    }
}

// 將 AppDelegate 標記為 @unchecked Sendable，避免 Swift 併發警告
extension AppDelegate: @unchecked Sendable {}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItemManager: StatusItemManager!
    var pasteboardManager: PasteboardManager!
    var textWindowManager: TextWindowManager!
    var openAIService: OpenAIService!
    var hotKeyManager: HotKeyManager!
    
    // 創建日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppDelegate")
    
    // Combine訂閱集合
    private var cancellables = Set<AnyCancellable>()
    
    // AppStateObserver實例
    private lazy var appStateObserver = AppStateObserver(appState: AppState.shared)
    
    var floatingButton: NSWindow?
    var textWindow: NSWindow?
    var settingsWindow: NSWindow?
    var swiftUIWindow: NSWindow?
    private var lastSelectedText: String?
    private var isRewriting = false
    private var isProcessingCopy = false
    
    // 新增顏色常量
    let addedTextColor = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // 深綠色
    let deletedTextColor = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // 深紅色
    
    private let compareThreshold = 100 // 累積多少字符後進行比較
    
    var currentTextView: NSTextView?
    var copyButton: NSButton?
    var statsView: NSTextField?
    var shortcutView: NSTextField?
    var settingsButton: NSButton?
    
    private var apiResponseText: String = ""
    private var apiReturnedText: String = ""

    var originalText: String = ""

    let customFont: NSFont

    // 系統提示詞
    private let systemPrompt = """
    你是一名專業的台灣繁體中文雜誌編輯，幫我檢查給定內容的錯字及語句文法。請特別注意以下規則：
    1. 中文與英文之間，中文與數字之間應有空格，例如 FLAC，JPEG，Google Search Console 。
    2. 注重標點符號的正確使用，包括避免中英文標點混用。例如：括號應該使用全形（）而非半形()。
    3. 修正不恰當的斷句，並注意句與句之間邏輯連貫性的順暢。
    4. 糾正錯字、錯詞和語法錯誤。
    5. 優化繁體中文表達，使文字更精簡、專業。
    
    請將更正後的內容放在兩個三個反引號之間。不需要講解修改的原因。只需要給出修改後的文本。
    """

    private var isApiKeyValid: Bool = false

    override init() {
        // 初始化自定義字體
        if let tsangerFont = NSFont(name: "TsangerJinKai01-W05", size: 14) {
            customFont = tsangerFont
        } else if let yuantiTC = NSFont(name: "Yuanti TC", size: 14) {
            customFont = yuantiTC
        } else {
            customFont = NSFont.systemFont(ofSize: 14)
        }
        
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 將啟動策略改為 .regular，使應用程式在 Dock 中顯示
        NSApp.setActivationPolicy(.regular)
        
        logger.info("應用程式啟動")
        
        // 設置AppKitBridge的AppDelegate引用
        AppKitBridge.shared.setAppDelegate(self)
        
        // 訂閱AppStateObserver的變更
        setupStateSubscriptions()
        
        // 初始化各個管理器
        initializeManagers()
        
        // 初始化UI元素
        setupUI()
        
        // 檢查API Key是否有效
        validateApiKey()
        
        // 打印初始狀態（用於調試）
        Task {
            await AppState.shared.printDebugState()
        }
        AppKitBridge.shared.printDebugState()
    }
    
    /// 設置與AppStateObserver的訂閱關係
    private func setupStateSubscriptions() {
        // 訂閱文本窗口狀態變化
        appStateObserver.$activeScreen
            .sink { [weak self] (activeScreen: ActiveScreen) in
                guard let self = self else { return }
                self.logger.debug("活動螢幕狀態變更: \(activeScreen)")
                
                // 根據活動螢幕狀態處理窗口
                switch activeScreen {
                case .main:
                    // 主界面，可能需要關閉其他窗口
                    if self.textWindow != nil {
                        DispatchQueue.main.async {
                            self.textWindow?.close()
                            self.textWindow = nil
                        }
                    }
                    if self.settingsWindow != nil {
                        DispatchQueue.main.async {
                            self.settingsWindow?.close()
                            self.settingsWindow = nil
                        }
                    }
                case .textCorrection:
                    // 文本校正界面，可能需要打開文本窗口
                    // 具體實現依賴於其他方法
                    break
                case .settings:
                    // 設置界面，可能需要打開設置窗口
                    // 具體實現依賴於其他方法
                    break
                }
            }
            .store(in: &cancellables)
        
        // 訂閱剪貼板監控狀態變化
        appStateObserver.$isMonitoringClipboard
            .sink { [weak self] (isEnabled: Bool) in
                // 使用主線程更新UI和APP狀態
                DispatchQueue.main.async {
                    self?.logger.debug("剪貼板監控狀態變更: \(isEnabled)")
                    if isEnabled {
                        self?.pasteboardManager?.startMonitoring()
                    } else {
                        self?.pasteboardManager?.stopMonitoring()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// 初始化各個管理器
    private func initializeManagers() {
        // 初始化管理器
        statusItemManager = StatusItemManager(appDelegate: self)
        pasteboardManager = PasteboardManager(appDelegate: self)
        textWindowManager = TextWindowManager(appDelegate: self)
        openAIService = OpenAIService()
        hotKeyManager = HotKeyManager(appDelegate: self)
        
        // 初始化熱鍵事件監聽（如果用戶已開啟）
        setupHotKeyIfEnabled()
        
        // 如果需要，啟動剪貼板監控
        Task {
            let shouldMonitor = await AppState.shared.isClipboardMonitoringEnabled
            if shouldMonitor {
                pasteboardManager.startMonitoring()
            }
        }
    }
    
    /// 如果用戶啟用了熱鍵，則設置熱鍵監聽
    private func setupHotKeyIfEnabled() {
        // 在隔離的上下文中檢查熱鍵設置
        Task {
            let hotkeysEnabled = await AppState.shared.isHotkeyActive
            let hotkey = await AppState.shared.hotKeyCharacter
            
            if hotkeysEnabled && !hotkey.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.hotKeyManager?.registerHotKey(hotkey)
                }
            }
        }
    }
    
    /// 設置基本UI元素
    private func setupUI() {
        // 此處可以初始化任何永久性UI組件
        logger.debug("設置基本UI元素")
    }
    
    /// 驗證API密鑰
    func validateApiKey() {
        Task {
            let key = getOpenAIApiKey()
            // 僅當密鑰非空時才進行驗證
            if !key.isEmpty {
                openAIService.validateAPIKey(key) { [weak self] isValid in
                    guard let self = self else { return }
                    Task {
                        await AppState.shared.updateApiKeyValid(isValid)
                    }
                    self.logger.info("API金鑰驗證結果: \(isValid)")
                }
            } else {
                self.logger.warning("API金鑰為空，無法驗證")
                Task {
                    await AppState.shared.updateApiKeyValid(false)
                }
            }
        }
    }
    
    /// 使用SwiftUI顯示文本校正窗口
    func showSwiftUITextWindow(text: String) {
        // 主線程UI更新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 如果窗口已存在，關閉它
            if let window = self.swiftUIWindow {
                window.close()
            }
            
            // 創建SwiftUI視圖
            let contentView = TextCorrectionView(text: text)
                .environmentObject(self.appStateObserver)
                .environment(\.appState, AppState.shared)
            
            // 創建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            // 配置窗口
            window.contentView = NSHostingView(rootView: contentView)
            window.title = "文本校正"
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            // 保存窗口引用
            self.swiftUIWindow = window
            
            // 更新AppState
            Task {
                await AppState.shared.setActiveScreen(.textCorrection)
            }
        }
    }
    
    /// 使用SwiftUI顯示設置窗口
    func showSettingsWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 如果窗口已存在，關閉它
            if let window = self.settingsWindow {
                window.close()
            }
            
            // 創建SwiftUI視圖
            let contentView = SettingsView()
                .environmentObject(self.appStateObserver)
                .environment(\.appState, AppState.shared)
            
            // 創建窗口
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            // 配置窗口
            window.contentView = NSHostingView(rootView: contentView)
            window.title = "設定"
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            // 保存窗口引用
            self.settingsWindow = window
            
            // 更新AppState
            Task {
                await AppState.shared.setActiveScreen(.settings)
            }
        }
    }

    // MARK: - OpenAI API 調用
    
    /// 將原始文本發送到OpenAI進行處理
    func processTextWithOpenAI(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        // 假設OpenAIService有一個processTextWithPrompt方法
        openAIService.processTextWithPrompt(
            text: text,
            systemPrompt: systemPrompt,
            apiKey: getOpenAIApiKey(),
            completion: completion
        )
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if window == textWindow {
            logger.debug("文本窗口將要關閉")
            Task {
                await AppState.shared.updateWindowState(type: "text", isOpen: false)
            }
            textWindow = nil
        } else if window == settingsWindow {
            logger.debug("設置窗口將要關閉")
            Task {
                await AppState.shared.updateWindowState(type: "settings", isOpen: false)
            }
        } else if window == swiftUIWindow {
            logger.debug("SwiftUI 文本窗口將要關閉")
            Task {
                await AppState.shared.updateWindowState(type: "text", isOpen: false)
            }
            swiftUIWindow = nil
        }
    }
}

// ... 其餘擴展保持不變 ...