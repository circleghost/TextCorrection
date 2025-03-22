//
//  ContentView.swift
//  TextCorrection
//
//  Created by 李元魁 on 2024/9/7.
//

import SwiftUI
import os.log

// 添加這個擴展來定義自定義通知名稱
extension Notification.Name {
    static let didSelectText = Notification.Name("didSelectText")
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedText: String = ""
    @State private var showPopup: Bool = false
    @State private var showFloatingButton: Bool = false
    @State private var showHelp: Bool = false
    @GestureState private var dragOffset = CGSize.zero
    
    private let logger = Logger(subsystem: "com.text.correction", category: "ContentView")

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                
                // 頂部區域 - 應用圖標和標題
                VStack(spacing: 15) {
                    Image(systemName: "text.bubble")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .foregroundColor(.blue)
                    
                    Text("錯字修正工具")
                        .font(.pungyu(size: 42, weight: .bold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 40)
                
                // 中間區域 - 說明 (整塊置中，內文左對齊)
                HStack {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 20) {
                        // 已移除「使用方法」文字，僅保留各項指令說明
                        InstructionRow(
                            icon: "text.cursor",
                            title: "選取文字",
                            description: "在任何應用程式中選擇需要修正的文字"
                        )
                        
                        InstructionRow(
                            icon: "keyboard",
                            title: "使用熱鍵",
                            description: "複製文字點擊按鈕或 Ctrl + Shift + 空白鍵來觸發比較功能"
                        )
                        
                        InstructionRow(
                            icon: "checkmark.bubble",
                            title: "查看結果",
                            description: "在結果視窗中檢視修正後的文字並複製"
                        )
                    }
                    .padding(.horizontal, 35)
                    .padding(.vertical, 35)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.windowBackgroundColor).opacity(0.6))
                    )
                    // 限制最大寬度，避免在超大螢幕上過度延伸
                    .frame(maxWidth: 600)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // 底部區域 - 按鈕與版本資訊
                VStack(spacing: 15) {
                    Button("查看使用指南") {
                        showHelp = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    HStack {
                        // 已改為顯示版本 0.1
                        Text("版本：0.1")
                            .font(.pungyu(size: 14))
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Button {
                            AppKitBridge.shared.showSettingsWindow()
                        } label: {
                            Label("設定", systemImage: "gear")
                                .font(.pungyu(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                .padding(.bottom, 20)
            }
            .padding()
            // 維持較大的預設視窗尺寸
            .frame(minWidth: 700, minHeight: 800)

            // 浮動按鈕 (若有需要才顯示)
            if showFloatingButton {
                FloatingButton(action: {
                    showPopup = true
                })
                .offset(x: 100 + dragOffset.width, y: 100 + dragOffset.height)
                .zIndex(1)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                )
            }

            // 彈出視窗
            if showPopup {
                PopupView(text: selectedText, isPresented: $showPopup)
            }
        }
        // 監聽文字選取通知
        .onReceive(NotificationCenter.default.publisher(for: .didSelectText)) { notification in
            if let text = notification.userInfo?["selectedText"] as? String {
                self.selectedText = text
                self.showFloatingButton = true
            }
        }
        // 顯示使用指南
        .sheet(isPresented: $showHelp) {
            WelcomeView(isPresented: $showHelp)
                .environmentObject(appState)
        }
    }
}

// 指令列表項目
struct InstructionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .frame(width: 45)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.pungyu(size: 24, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.pungyu(size: 18))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}

// 主要按鈕樣式
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pungyu(size: 20, weight: .semibold))
            .padding(.horizontal, 35)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

// 浮動按鈕
struct FloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "text.quote")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(radius: 5)
        }
        .frame(width: 80, height: 80)
    }
}

// 彈出視窗
struct PopupView: View {
    let text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("選取的文字：")
                .font(.pungyu(size: 22, weight: .semibold))
            
            Text(text)
                .font(.pungyu(size: 18))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            Button("關閉") {
                isPresented = false
            }
            .font(.pungyu(size: 18, weight: .medium))
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding(25)
        .background(Color.white)
        .cornerRadius(15)
        .shadow(radius: 10)
        .frame(maxWidth: 350)
        .transition(.scale)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
