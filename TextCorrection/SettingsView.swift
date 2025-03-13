import SwiftUI
import KeychainAccess
import os.log

struct SettingsView: View, @unchecked Sendable {
    @State private var apiKey: String = ""
    @State private var isSaving: Bool = false
    @State private var message: String = ""
    @State private var showMessage: Bool = false
    @State private var isSuccess: Bool = false
    
    // 使用 AppState 進行狀態管理
    @EnvironmentObject private var appState: AppState
    
    // 環境變數，用於關閉視窗
    @Environment(\.dismiss) private var dismiss
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "SettingsView")
    
    private let keychain = Keychain(service: "com.yourcompany.TextCorrection")
    
    var body: some View {
        VStack(spacing: 20) {
            Text("文字校正設定")
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 10)
            
            ScrollView {
                VStack(spacing: 15) {
                    // MARK: - 介面設定
                    GroupBox(label: Text("介面設定")) {
                        VStack(spacing: 10) {
                            // 視覺效果開關
                            Toggle(isOn: Binding(
                                get: { appState.isVisualEffectsEnabled },
                                set: { appState.updateVisualEffects(enabled: $0) }
                            )) {
                                Text("啟用視覺效果")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                            
                            // 粒子效果開關
                            Toggle(isOn: Binding(
                                get: { appState.isParticleEffectsEnabled },
                                set: { appState.updateParticleEffects(enabled: $0) }
                            )) {
                                Text("啟用粒子效果")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                            
                            // 動畫開關
                            Toggle(isOn: Binding(
                                get: { appState.isAnimationsEnabled },
                                set: { appState.updateAnimations(enabled: $0) }
                            )) {
                                Text("啟用動畫")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                            
                            // 高品質效果開關
                            Toggle(isOn: Binding(
                                get: { appState.isHighQualityEffectsEnabled },
                                set: { appState.updateHighQualityEffects(enabled: $0) }
                            )) {
                                Text("高品質效果")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                        }
                        .padding(.vertical, 5)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - 功能設定
                    GroupBox(label: Text("功能設定")) {
                        VStack(alignment: .leading, spacing: 10) {
                            // 剪貼板監控開關
                            Toggle(isOn: Binding(
                                get: { appState.isClipboardMonitoringEnabled },
                                set: { appState.updateClipboardMonitoring(enabled: $0) }
                            )) {
                                Text("啟用剪貼板監控")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                            
                            // 熱鍵啟用開關
                            Toggle(isOn: Binding(
                                get: { appState.isHotkeyActive },
                                set: { appState.updateHotkey(active: $0) }
                            )) {
                                Text("啟用熱鍵")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                        }
                        .padding(.vertical, 5)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - 熱鍵設定
                    GroupBox(label: Text("熱鍵設定")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("校正文字:")
                                    .font(.system(size: 14))
                                Spacer()
                                Text("⇧+⌃+Space")
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(5)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(5)
                            }
                            
                            HStack {
                                Text("替代熱鍵:")
                                    .font(.system(size: 14))
                                Spacer()
                                Text("⌘+⌥+T")
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(5)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(5)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - API 設定
                    GroupBox(label: Text("API 設定")) {
                        VStack(alignment: .leading, spacing: 10) {
                            SecureField("輸入 OpenAI API 金鑰", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.vertical, 4)
                            
                            HStack {
                                Button(action: saveApiKey) {
                                    HStack {
                                        if isSaving {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 16, height: 16)
                                        }
                                        Text("儲存 API 金鑰")
                                    }
                                    .frame(minWidth: 120)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isSaving || apiKey.isEmpty)
                                
                                Spacer()
                                
                                // API 狀態指示
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(appState.isApiKeyValid ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(appState.isApiKeyValid ? "已驗證" : "未驗證")
                                        .font(.system(size: 12))
                                        .foregroundColor(appState.isApiKeyValid ? .green : .red)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .padding(.horizontal)
                }
            }
            
            Button(action: {
                logger.debug("重置設定按鈕被點擊")
                appState.resetSettings()
                showSuccessMessage("所有設定已重置")
            }) {
                Text("重置所有設定")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            
            // 關於資訊
            HStack {
                Text("TextCorrection")
                    .font(.system(size: 12, weight: .medium))
                Text("版本 1.0")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 5)
        }
        .frame(width: 350, height: 430)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: {
            logger.debug("SettingsView 出現")
            loadApiKey()
            updateWindowState(isOpen: true)
        })
        .onDisappear {
            logger.debug("SettingsView 消失")
            updateWindowState(isOpen: false)
        }
        .alert(isSuccess ? "成功" : "錯誤", isPresented: $showMessage) {
            Button("確定") {
                if isSuccess {
                    dismiss()
                }
            }
        } message: {
            Text(message)
        }
    }
    
    // 更新窗口狀態
    private func updateWindowState(isOpen: Bool) {
        appState.isSettingsWindowOpen = isOpen
        logger.debug("設置窗口狀態更新為: \(isOpen)")
        // AppKitBridge.shared.notifyWindowStateChanged(type: "settings", isVisible: isOpen)
    }
    
    private func loadApiKey() {
        do {
            if let storedKey = try keychain.get("OpenAIApiKey") {
                apiKey = storedKey
                logger.debug("已從鑰匙圈載入API金鑰")
            }
        } catch {
            logger.error("載入 API 金鑰時發生錯誤: \(error.localizedDescription)")
        }
    }
    
    private func saveApiKey() {
        guard !apiKey.isEmpty else { return }
        
        logger.debug("正在保存API金鑰")
        isSaving = true
        
        // 模擬非同步操作，實際應用中可能需要驗證API key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            do {
                try keychain.set(apiKey, key: "OpenAIApiKey")
                
                // 記錄成功並更新UI狀態
                logger.info("API金鑰已成功保存到鑰匙圈")
                appState.isApiKeyValid = true
                showSuccessMessage("API 金鑰已儲存")
            } catch {
                // 記錄錯誤並顯示錯誤訊息
                logger.error("保存API金鑰失敗: \(error.localizedDescription)")
                showErrorMessage("無法儲存 API 金鑰: \(error.localizedDescription)")
            }
            
            isSaving = false
        }
    }
    
    private func showSuccessMessage(_ text: String) {
        message = text
        isSuccess = true
        showMessage = true
        
        // 添加通知
        appState.addNotification(title: "成功", message: text, type: .success)
    }
    
    private func showErrorMessage(_ text: String) {
        message = text
        isSuccess = false
        showMessage = true
        
        // 添加通知
        appState.addNotification(title: "錯誤", message: text, type: .error)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
} 