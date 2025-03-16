// TextCorrection/AppKitBridge.swift 
// 該文件定義了 AppKit 與 SwiftUI 之間的橋接層

import Foundation
import SwiftUI
import Combine
import Cocoa
import os.log

/// AppKitBridge: 負責AppKit和SwiftUI之間的通信
/// 提供一個統一的界面來處理跨架構的互動
public class AppKitBridge: ObservableObject {
    // 單例模式，簡化使用
    public static let shared = AppKitBridge()
    
    // 創建日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppKitBridge")
    
    // 持有AppDelegate的弱引用
    weak var appDelegate: AppDelegate?
    
    // 持有AppStateObserver的引用
    private lazy var appStateObserver = AppStateObserver(appState: AppState.shared)
    
    // 訂閱集合，用於管理所有的Combine訂閱
    private var cancellables = Set<AnyCancellable>()
    
    // 窗口顯示狀態
    @Published var isTextWindowVisible: Bool = false
    @Published var isSettingsWindowVisible: Bool = false
    @Published var isFloatingButtonVisible: Bool = false
    
    // 剪貼板相關狀態
    @Published var hasCopiedText: Bool = false
    @Published var lastCopiedText: String = ""
    
    // 文本處理狀態（補充AppState中的內容）
    @Published var isTextBeingProcessed: Bool = false
    
    // 私有初始化函數
    private init() {
        logger.info("AppKitBridge 初始化")
        
        // 從AppStateObserver訂閱相關數據變化
        setupSubscriptions()
    }
    
    /// 設置與AppStateObserver的訂閱關係
    private func setupSubscriptions() {
        // 訂閱AppStateObserver的isProcessing狀態
        appStateObserver.$isProcessing
            .sink { [weak self] isProcessing in
                guard let self = self else { return }
                self.isTextBeingProcessed = isProcessing
                self.logger.debug("文本處理狀態更新: \(isProcessing)")
            }
            .store(in: &cancellables)
        
        // 訂閱AppStateObserver的原始文本變化
        appStateObserver.$originalText
            .filter { !$0.isEmpty }
            .sink { [weak self] text in
                guard let self = self else { return }
                self.logger.debug("收到新的原始文本，長度: \(text.count)字符")
            }
            .store(in: &cancellables)
        
        // 根據activeScreen訂閱窗口可見性狀態
        appStateObserver.$activeScreen
            .sink { [weak self] activeScreen in
                guard let self = self else { return }
                switch activeScreen {
                case .textCorrection:
                    self.isTextWindowVisible = true
                    self.isSettingsWindowVisible = false
                case .settings:
                    self.isTextWindowVisible = false
                    self.isSettingsWindowVisible = true
                case .main:
                    self.isTextWindowVisible = false
                    self.isSettingsWindowVisible = false
                }
            }
            .store(in: &cancellables)
    }
    
    /// 設置AppDelegate引用
    func setAppDelegate(_ delegate: AppDelegate) {
        self.appDelegate = delegate
        logger.info("AppDelegate引用已設置")
    }
    
    // MARK: - 窗口管理方法
    
    /// 顯示SwiftUI文本校正窗口
    func showTextCorrectionWindow(withText text: String) {
        logger.info("請求顯示文本校正窗口，文本長度: \(text.count)字符")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let appDelegate = self.appDelegate else {
                self?.logger.error("無法顯示文本校正窗口：AppDelegate為nil")
                return
            }
            
            // 更新AppState
            Task {
                await AppState.shared.updateTextInfo(originalText: text, correctedText: "")
            }
            
            // 使用AppDelegate顯示窗口
            appDelegate.showSwiftUITextWindow(text: text)
            
            // 更新窗口可見狀態
            self.isTextWindowVisible = true
        }
    }
    
    /// 顯示設置窗口
    func showSettingsWindow() {
        logger.info("請求顯示設置窗口")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let appDelegate = self.appDelegate else {
                self?.logger.error("無法顯示設置窗口：AppDelegate為nil")
                return
            }
            
            // 使用AppDelegate顯示窗口
            appDelegate.showSettingsWindow()
            
            // 更新窗口可見狀態
            self.isSettingsWindowVisible = true
        }
    }
    
    /// 顯示浮動按鈕
    func showFloatingButton() {
        logger.info("請求顯示浮動按鈕")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let appDelegate = self.appDelegate else {
                self?.logger.error("無法顯示浮動按鈕：AppDelegate為nil")
                return
            }
            
            appDelegate.showFloatingButton()
            self.isFloatingButtonVisible = true
        }
    }
    
    /// 隱藏浮動按鈕
    func hideFloatingButton() {
        logger.info("請求隱藏浮動按鈕")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let appDelegate = self.appDelegate else {
                self?.logger.error("無法隱藏浮動按鈕：AppDelegate為nil")
                return
            }
            
            appDelegate.hideFloatingButton()
            self.isFloatingButtonVisible = false
        }
    }
    
    // MARK: - 文本處理方法
    
    /// 處理剪貼板文本
    func processClipboardText() {
        logger.info("處理剪貼板文本")
        
        // 從剪貼板獲取文本
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            logger.warning("剪貼板為空或不包含文本")
            return
        }
        
        // 顯示文本窗口並處理文本
        showTextCorrectionWindow(withText: text)
        
        // 觸發處理流程
        if let appDelegate = appDelegate {
            // 假設appDelegate具有相應的處理方法
            appDelegate.processTextWithOpenAI(text: text) { [weak self] result in
                switch result {
                case .success(let correctedText):
                    // 更新AppState
                    Task {
                        await AppState.shared.updateTextInfo(originalText: text, correctedText: correctedText)
                    }
                    self?.logger.info("文本處理成功，修正文本長度: \(correctedText.count)字符")
                    
                case .failure(let error):
                    // 記錄錯誤
                    self?.logger.error("文本處理失敗：\(error.localizedDescription)")
                    
                    // 更新錯誤狀態
                    Task {
                        await AppState.shared.updateErrorMessage(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    /// 將校正後的文本複製到剪貼板並嘗試粘貼
    func copyAndPasteRewritten() {
        logger.info("開始複製校正文本到剪貼板")
        
        Task {
            let correctedText = await AppState.shared.correctedText
            
            // 確保有校正後的文本
            if correctedText.isEmpty {
                logger.warning("沒有校正文本可以複製")
                return
            }
            
            // 複製到剪貼板
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(correctedText, forType: .string)
            
            logger.info("文本已複製到剪貼板，嘗試粘貼")
            
            // 嘗試模擬粘貼操作 (由於安全限制，這可能不總是有效)
            // 使用AppleScript或其他方法可能會更可靠
        }
    }
    
    // MARK: - 調試方法
    
    /// 打印調試信息
    func printDebugState() {
        logger.info("""
        ----- AppKitBridge 調試信息 -----
        窗口狀態:
          - 文本窗口可見: \(isTextWindowVisible)
          - 設置窗口可見: \(isSettingsWindowVisible)
          - 浮動按鈕可見: \(isFloatingButtonVisible)
        
        剪貼板狀態:
          - 已複製文本: \(hasCopiedText)
          - 剪貼板文本長度: \(lastCopiedText.count)
        
        處理狀態:
          - 正在處理文本: \(isTextBeingProcessed)
        ----- AppKitBridge 調試信息結束 -----
        """)
    }
} 