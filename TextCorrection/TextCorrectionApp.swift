//
//  TextCorrectionApp.swift
//  TextCorrection
//
//  Created by 李元魁 on 2024/9/7.
//

import SwiftUI
import AppKit

@main
struct TextCorrectionApp: App, @unchecked Sendable {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            EmptyView()
                .onAppear {
                    // AppState.shared 已在全局可用，不需要透過 environmentObject 傳遞
                    // 如果需要，可以在這裡額外初始化 appState
                }
        }
        // 在 macOS 12.0 中不支持 environmentObject，改用 AppState 的單例模式
    }
}

