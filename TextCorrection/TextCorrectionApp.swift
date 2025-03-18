//
//  TextCorrectionApp.swift
//  TextCorrection
//
//  Created by 李元魁 on 2024/9/7.
//

import SwiftUI
import AppKit
import os.log

@main
struct TextCorrectionApp: App, @unchecked Sendable {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextCorrectionApp")
    
    init() {
        logger.info("TextCorrectionApp 初始化")
        
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
        // 在這裡捕獲 appDelegate，避免在 onAppear 閉包中使用 self
        let appDelegateRef = self.appDelegate
        
        return Settings {
            EmptyView()
                .onAppear {
                    logger.info("TextCorrectionApp 視圖已出現")
                    
                    // 使用捕獲的 appDelegateRef 而不是 self.appDelegate
                    AppKitBridge.shared.setAppDelegate(appDelegateRef)
                }
        }
    }
}

