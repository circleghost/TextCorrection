// TextCorrection/AppKitBridge.swift 
// 該文件定義了 AppKit 與 SwiftUI 之間的橋接層

import Foundation
import AppKit
import Combine
import SwiftUI
import os.log

/// AppKitBridge: 負責AppKit和SwiftUI之間的通信
/// 提供一個統一的界面來處理跨架構的互動
@MainActor
class AppKitBridge: ObservableObject {
    // 單例實例
    static let shared = AppKitBridge()
    
    // 發布的屬性，用於SwiftUI綁定
    @Published var isTextWindowVisible: Bool = false
    @Published var isSettingsWindowVisible: Bool = false
    @Published var isFloatingButtonVisible: Bool = false
    @Published var hasCopiedText: Bool = false
    @Published var lastCopiedText: String = ""
    @Published var isTextBeingProcessed: Bool = false
    
    // 私有屬性
    private var appDelegate: AppDelegate?
    private var logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppKitBridge")
    
    // 使用AppState
    private var appState: AppState
    private var appStateObserver: AppStateObserver
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init(appDelegate: AppDelegate? = nil) {
        self.appDelegate = appDelegate
        self.appState = AppState.shared
        self.appStateObserver = AppStateObserver()
        
        logger.info("初始化AppKitBridge")
        
        setupSubscriptions()
    }
    
    // MARK: - 設置AppDelegate
    
    /// 設置AppDelegate引用
    func setAppDelegate(_ delegate: AppDelegate) {
        logger.info("設置AppDelegate引用")
        // 這個方法不需要實際做任何事情，因為我們已經通過計算屬性獲取AppDelegate
        // 但是為了與TextCorrectionApp.swift中的調用兼容，我們保留這個方法
    }
    
    // MARK: - 訂閱設置
    
    private func setupSubscriptions() {
        // 訂閱AppState的isProcessing屬性
        appState.$isProcessing
            .receive(on: RunLoop.main)
            .sink { [weak self] isProcessing in
                self?.isTextBeingProcessed = isProcessing
            }
            .store(in: &cancellables)
        
        // 訂閱AppState的windowStates屬性
        appState.$windowStates
            .receive(on: RunLoop.main)
            .sink { [weak self] windowStates in
                guard let self = self else { return }
                self.isTextWindowVisible = windowStates["text"] ?? false
                self.isSettingsWindowVisible = windowStates["settings"] ?? false
                self.isFloatingButtonVisible = windowStates["floatingButton"] ?? false
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 窗口管理方法
    
    /// 顯示文本窗口
    func showTextWindow() {
        NSLog("AppKitBridge: 請求顯示文本窗口")
        
        isTextWindowVisible = true
        appStateObserver.updateWindowState(type: "text", isOpen: true)
        appDelegate?.showTextWindow()
    }
    
    /// 隱藏文本窗口
    func hideTextWindow() {
        NSLog("AppKitBridge: 請求隱藏文本窗口")
        
        isTextWindowVisible = false
        appStateObserver.updateWindowState(type: "text", isOpen: false)
        appDelegate?.hideTextWindow()
    }
    
    /// 顯示設置窗口
    func showSettingsWindow() {
        NSLog("AppKitBridge: 請求顯示設置窗口")
        
        isSettingsWindowVisible = true
        appStateObserver.updateWindowState(type: "settings", isOpen: true)
        appDelegate?.showSettings()
    }
    
    /// 隱藏設置窗口
    func hideSettingsWindow() {
        NSLog("AppKitBridge: 請求隱藏設置窗口")
        
        isSettingsWindowVisible = false
        appStateObserver.updateWindowState(type: "settings", isOpen: false)
        appDelegate?.hideSettingsWindow()
    }
    
    /// 顯示浮動按鈕
    func showFloatingButton() {
        NSLog("AppKitBridge: 請求顯示浮動按鈕")
        
        isFloatingButtonVisible = true
        appStateObserver.updateWindowState(type: "floatingButton", isOpen: true)
        appDelegate?.showFloatingButton()
    }
    
    /// 隱藏浮動按鈕
    func hideFloatingButton() {
        NSLog("AppKitBridge: 請求隱藏浮動按鈕")
        
        isFloatingButtonVisible = false
        appStateObserver.updateWindowState(type: "floatingButton", isOpen: false)
        appDelegate?.hideFloatingButton()
    }
    
    // MARK: - 剪貼板處理方法
    
    /// 處理剪貼板文本
    @MainActor
    func processClipboardText() {
        NSLog("AppKitBridge: 處理剪貼板文本")
        
        guard let clipboard = NSPasteboard.general.string(forType: .string) else {
            NSLog("AppKitBridge: 剪貼板中沒有文本")
            return
        }
        
        lastCopiedText = clipboard
        hasCopiedText = true
        
        if !clipboard.isEmpty {
            NSLog("AppKitBridge: 剪貼板文本長度: \(clipboard.count)")
            
            Task {
                await appDelegate?.processTextWithOpenAI(text: clipboard)
            }
        }
    }
    
    /// 複製文本到剪貼板
    func copyTextToClipboard(_ text: String) {
        NSLog("AppKitBridge: 複製文本到剪貼板")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - 應用程序控制方法
    
    /// 退出應用程序
    func quitApplication() {
        NSLog("AppKitBridge: 請求退出應用程序")
        NSApplication.shared.terminate(nil)
    }
    
    /// 顯示關於窗口
    func showAboutPanel() {
        NSLog("AppKitBridge: 請求顯示關於窗口")
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
    
    // MARK: - 調試方法
    
    /// 打印調試信息
    func printDebugState() {
        NSLog("""
        ----- AppKitBridge 調試信息 -----
        文本窗口可見: \(self.isTextWindowVisible)
        設置窗口可見: \(self.isSettingsWindowVisible)
        浮動按鈕可見: \(self.isFloatingButtonVisible)
        剪貼板有文本: \(self.hasCopiedText)
        剪貼板文本長度: \(self.lastCopiedText.count)
        文本處理中: \(self.isTextBeingProcessed)
        ----- AppKitBridge 調試信息結束 -----
        """)
    }
} 