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
        
        // 從AppState訂閱相關數據變化
        setupSubscriptions()
    }
    
    /// 設置與AppState的訂閱關係
    private func setupSubscriptions() {
        // 訂閱AppState的isProcessing狀態
        AppState.shared.$isProcessing
            .sink { [weak self] isProcessing in
                guard let self = self else { return }
                self.isTextBeingProcessed = isProcessing
                self.logger.debug("文本處理狀態更新: \(isProcessing)")
            }
            .store(in: &cancellables)
        
        // 訂閱AppState的原始文本變化
        AppState.shared.$originalText
            .filter { !$0.isEmpty }
            .sink { [weak self] text in
                guard let self = self else { return }
                self.logger.debug("收到新的原始文本，長度: \(text.count)字符")
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
            AppState.shared.originalText = text
            
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
            
            appDelegate.showSettings()
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
    
    /// 開始處理文本
    func processText(_ text: String) {
        logger.info("請求處理文本，長度: \(text.count)字符")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let appDelegate = self.appDelegate else {
                self?.logger.error("無法處理文本：AppDelegate為nil")
                return
            }
            
            AppState.shared.originalText = text
            AppState.shared.isProcessing = true
            
            appDelegate.rewriteText()
        }
    }
    
    /// 複製並貼上校正後的文本
    func copyAndPasteCorrectedText() {
        logger.info("請求複製並貼上校正後的文本")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let appDelegate = self.appDelegate else {
                self?.logger.error("無法複製貼上：AppDelegate為nil")
                return
            }
            
            appDelegate.copyAndPasteRewrittenText()
        }
    }
    
    // MARK: - 事件處理方法
    
    /// 從AppKit通知文本已複製
    func notifyTextCopied(_ text: String) {
        logger.debug("通知：文本已複製，長度: \(text.count)字符")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.lastCopiedText = text
            self.hasCopiedText = true
        }
    }
    
    /// 從AppKit通知窗口狀態變化
    func notifyWindowStateChanged(type: String, isVisible: Bool) {
        logger.debug("通知：窗口狀態變化 - \(type): \(isVisible)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch type {
            case "text":
                self.isTextWindowVisible = isVisible
            case "settings":
                self.isSettingsWindowVisible = isVisible
            case "floatingButton":
                self.isFloatingButtonVisible = isVisible
            default:
                self.logger.warning("收到未知的窗口類型：\(type)")
            }
        }
    }
    
    // MARK: - 調試方法
    
    /// 打印當前狀態（用於調試）
    func printDebugState() {
        logger.debug("""
        ===== AppKitBridge 狀態 =====
        文本窗口可見: \(self.isTextWindowVisible)
        設置窗口可見: \(self.isSettingsWindowVisible)
        浮動按鈕可見: \(self.isFloatingButtonVisible)
        有複製的文本: \(self.hasCopiedText)
        文本處理中: \(self.isTextBeingProcessed)
        ===========================
        """)
    }
} 