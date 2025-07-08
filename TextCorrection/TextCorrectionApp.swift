//
//  TextCorrectionApp.swift
//  TextCorrection
//
//  Created by 李元魁 on 2024/9/7.
//

import SwiftUI
import Cocoa
import CoreText
import os.log
import Combine
import KeychainAccess

@main
struct TextCorrectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.text.correction", category: "App")
    
    init() {
        logger.info("TextCorrectionApp 初始化")
        
        // 檢查系統版本
        checkSystemVersion()
        
        // 載入自定義字體
        loadCustomFonts()
        
        // 設置應用程式菜單
        setupApplicationMenu()
        
        // 在閉包外捕獲 appDelegate 的引用
        let appDelegateRef = self.appDelegate
        
        // 確保 AppKitBridge 能夠訪問 AppDelegate
        Task { [appDelegateRef] in
            // 使用延遲來確保 appDelegate 已完全初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [appDelegateRef] in
                // 在閉包內使用捕獲的 appDelegateRef 而不是 self.appDelegate
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextCorrectionApp")
                    .info("設置 AppKitBridge 的 AppDelegate 引用")
                AppKitBridge.shared.setAppDelegate(appDelegateRef)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            // 直接顯示歡迎頁面而不是 ContentView
            Group {
                if !appState.hasShownWelcomeScreen {
                    WelcomeView()
                        .environmentObject(appState)
                        .frame(width: 800, height: 650)
                } else {
                    ContentView()
                        .environmentObject(appState)
                }
            }
            .onAppear {
                // 檢查權限
                Task { @MainActor in
                    AccessibilityManager.checkPermissionsOnLaunch()
                }
                
                // 檢查 API 金鑰有效性
                Task {
                    do {
                        // 先嘗試獲取已儲存的 API 金鑰
                        let keychain = KeychainAccess.Keychain(service: "com.yourcompany.TextCorrection")
                        if let savedApiKey = try keychain.get("openai_api_key"), !savedApiKey.isEmpty {
                            // 已有 API 金鑰，檢查有效性
                            if appState.isApiKeyValid {
                                // API 金鑰已有效，不需要顯示設定視窗
                                logger.info("已有有效的 API 金鑰，不顯示設定視窗")
                                return
                            }
                        }
                        
                        // 延遲一段時間再顯示設定視窗，確保應用程式完全載入
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
                        
                        // 檢查是否已開啟設定視窗
                        if appState.isSettingsWindowOpen {
                            // 找尋並置前現有視窗
                            for window in NSApp.windows where window.title == "設定" {
                                window.makeKeyAndOrderFront(nil)
                                return
                            }
                        }
                        
                        // 開啟設定視窗，使用者可以輸入 API 金鑰
                        logger.info("無有效 API 金鑰，顯示設定視窗")
                        await MainActor.run {
                            // 使用AppKitBridge統一打開設定窗口
                            AppKitBridge.shared.showSettingsWindow()
                        }
                    } catch {
                        logger.error("檢查 API 金鑰時發生錯誤: \(error.localizedDescription)")
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 添加自定義菜單
            CommandGroup(replacing: .appInfo) {
                Button("關於錯字修正") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "錯字修正",
                            NSApplication.AboutPanelOptionKey.applicationVersion: Utilities.getAppVersion(),
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "一個幫助快速修正錯別字的工具",
                                attributes: [.foregroundColor: NSColor.textColor]
                            )
                        ]
                    )
                }
                
                // 在「關於」選項後添加設定選項
                Button("偏好設定...") {
                    AppKitBridge.shared.showSettingsWindow()
                }
            }
            
            CommandGroup(replacing: .help) {
                Button("使用指南") {
                    appDelegate.showWelcomeView()
                }
                
                Button("提交反饋") {
                    appDelegate.showFeedbackView()
                }
            }
            
            // 屏蔽默認的設定菜單項
            CommandGroup(replacing: .appSettings) { 
                EmptyView()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func checkSystemVersion() {
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
    }
    
    private func loadCustomFonts() {
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
    
    private func setupApplicationMenu() {
        // 獲取主菜單
        let mainMenu = NSApplication.shared.mainMenu ?? NSMenu(title: "MainMenu")
        
        // 創建「工具」菜單
        let toolsMenu = NSMenu(title: "工具")
        let toolsMenuItem = NSMenuItem(title: "工具", action: nil, keyEquivalent: "")
        toolsMenuItem.submenu = toolsMenu
        
        // 添加「顯示日誌」選項
        let showLogsItem = NSMenuItem(
            title: "顯示日誌視窗",
            action: #selector(AppDelegate.showLogsView),
            keyEquivalent: "l"
        )
        showLogsItem.keyEquivalentModifierMask = [.command, .option]
        showLogsItem.target = appDelegate
        toolsMenu.addItem(showLogsItem)
        
        // 添加「建立診斷報告」選項
        let createReportItem = NSMenuItem(
            title: "建立診斷報告",
            action: #selector(AppDelegate.createDiagnosticReport),
            keyEquivalent: "d"
        )
        createReportItem.keyEquivalentModifierMask = [.command, .option]
        createReportItem.target = appDelegate
        toolsMenu.addItem(createReportItem)
        
        // 如果工具菜單不存在，則添加到主菜單
        if mainMenu.item(withTitle: "工具") == nil {
            // 確保索引不會是負數
            let insertIndex = max(0, mainMenu.items.count - 1)
            mainMenu.insertItem(toolsMenuItem, at: insertIndex)
        }
        
        // 確保主菜單被設置
        if NSApplication.shared.mainMenu == nil {
            NSApplication.shared.mainMenu = mainMenu
        }
        
        // 記錄菜單設置完成
        logger.info("應用程式菜單設置完成，已添加日誌視窗快捷鍵 Command+Option+L")
    }
}

