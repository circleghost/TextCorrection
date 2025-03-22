import SwiftUI
import KeychainAccess
import os.log

// MARK: - 常量
private enum UIConstants {
    static let windowWidth: CGFloat = 450
    static let windowHeight: CGFloat = 600
    static let cornerRadius: CGFloat = 6
    static let spacing: CGFloat = 16
    static let groupSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 32
    
    static let primaryColor = Color(hex: "0366D6")
    static let secondaryColor = Color(hex: "F5F5F5")
    static let accentColor = Color(hex: "2188FF")
    static let dangerColor = Color(hex: "D73A49")
    static let successColor = Color(hex: "28A745")
    
    static let titleFont = Font.pungyu(size: 24, weight: .bold)
    static let sectionFont = Font.pungyu(size: 16, weight: .semibold)
    static let sectionHeaderFont = Font.pungyu(size: 14, weight: .semibold)
    static let bodyFont = Font.pungyu(size: 14, weight: .regular)
    static let captionFont = Font.pungyu(size: 12, weight: .regular)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 自定義按鈕樣式
struct LinearButtonStyle: ButtonStyle {
    var isPrimary = true
    var isDanger = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UIConstants.bodyFont)
            .foregroundColor(getTextColor(configuration: configuration))
            .padding(.horizontal, UIConstants.spacing)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .fill(getBackgroundColor(configuration: configuration))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
    
    private func getBackgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            if isDanger {
                return UIConstants.dangerColor.opacity(0.8)
            } else if isPrimary {
                return UIConstants.primaryColor.opacity(0.8)
            } else {
                return UIConstants.secondaryColor.opacity(0.8)
            }
        } else {
            if isDanger {
                return UIConstants.dangerColor
            } else if isPrimary {
                return UIConstants.primaryColor
            } else {
                return UIConstants.secondaryColor
            }
        }
    }
    
    private func getTextColor(configuration: Configuration) -> Color {
        if isPrimary || isDanger {
            return .white
        } else {
            return .primary
        }
    }
}

// MARK: - 自定義Toggle樣式
struct LinearToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(UIConstants.bodyFont)
            
            Spacer()
            
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? UIConstants.primaryColor : Color.gray.opacity(0.3))
                    .frame(width: 50, height: 28)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 1)
                    .offset(x: configuration.isOn ? 11 : -11)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            }
            .onTapGesture {
                withAnimation {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - 卡片背景樣式
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(UIConstants.spacing)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
            .padding(.horizontal, UIConstants.spacing)
            .padding(.vertical, UIConstants.spacing / 2)
    }
}

extension View {
    func cardStyle() -> some View {
        self.modifier(CardBackground())
    }
}

// MARK: - 主視圖
struct SettingsView: View, @unchecked Sendable {
    @State private var apiKey: String = ""
    @State private var isSaving: Bool = false
    @State private var message: String = ""
    @State private var showMessage: Bool = false
    @State private var isSuccess: Bool = false
    @State private var selectedTab = 0
    @State private var showHotkeyCustomizationSheet = false
    @State private var tempModifiers: [String] = []
    @State private var tempCharacter: String = ""
    @State private var isValidating: Bool = false
    @StateObject private var appSettings = AppSettings.shared
    
    // 使用 AppState 進行狀態管理
    @EnvironmentObject private var appState: AppState
    
    // 環境變數，用於關閉視窗
    @Environment(\.dismiss) private var dismiss
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "SettingsView")
    
    private let keychain = Keychain(service: "com.yourcompany.TextCorrection")
    private let openAIService = OpenAIService()
    
    var body: some View {
        VStack(spacing: 0) {
            // 頂部標題區域
                            HStack {
                Text("TextCorrection 設定")
                    .font(UIConstants.titleFont)
                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(UIConstants.spacing)
            .padding(.bottom, UIConstants.spacing / 2)
            
            // 分頁選擇
            HStack(spacing: UIConstants.spacing) {
                tabButton(title: "一般設定", systemImage: "gear", tag: 0)
                tabButton(title: "API設定", systemImage: "key", tag: 1)
                tabButton(title: "進階設定", systemImage: "slider.horizontal.3", tag: 2)
                
                Spacer()
            }
            .padding(.horizontal, UIConstants.spacing)
            .padding(.bottom, UIConstants.spacing)
            
            Divider()
                .padding(.bottom, UIConstants.spacing)
            
            // 主內容區
            ScrollView {
                VStack(spacing: UIConstants.sectionSpacing) {
                    if selectedTab == 0 {
                        generalSettingsView
                    } else if selectedTab == 1 {
                        apiSettingsView
                    } else {
                        advancedSettingsView
                    }
                }
                .padding(.bottom, UIConstants.spacing * 2)
            }
            
            Divider()
                .padding(.top, UIConstants.spacing)
            
            // 底部版本資訊和重置按鈕
            HStack {
            Button(action: {
                logger.debug("重置設定按鈕被點擊")
                appState.resetSettings()
                showSuccessMessage("所有設定已重置")
            }) {
                Text("重置所有設定")
                            .font(UIConstants.bodyFont)
            }
                .buttonStyle(LinearButtonStyle(isPrimary: false, isDanger: true))
                
                Spacer()
            
            HStack {
                Text("TextCorrection")
                            .font(UIConstants.captionFont.weight(.medium))
                Text("版本 1.0")
                            .font(UIConstants.captionFont)
                    .foregroundColor(.gray)
            }
                }
                .padding(UIConstants.spacing)
        }
        .frame(width: UIConstants.windowWidth, height: UIConstants.windowHeight)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: {
            logger.debug("SettingsView 出現")
            loadApiKey()
            updateWindowState(isOpen: true)
            
            // 如果 API 金鑰無效，自動切換到 API 設定頁面
            if !appState.isApiKeyValid {
                selectedTab = 1
                
                // 如果 API 金鑰為空，顯示一個提示訊息
                if apiKey.isEmpty {
                    message = "請設定 OpenAI API 金鑰以啟用文字校正功能"
                    isSuccess = false
                    showMessage = true
                }
            }
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
    
    // 頁籤按鈕
    private func tabButton(title: String, systemImage: String, tag: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                Text(title)
                    .font(UIConstants.bodyFont)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .fill(selectedTab == tag ? 
                          UIConstants.primaryColor.opacity(0.1) : 
                          Color.clear)
            )
            .foregroundColor(selectedTab == tag ? 
                             UIConstants.primaryColor : 
                             .primary)
        }
        .buttonStyle(.plain)
    }
    
    // 一般設定視圖
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: UIConstants.groupSpacing) {
            // 熱鍵設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("熱鍵設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: Binding(
                        get: { appState.isHotkeyActive },
                        set: { appState.updateHotkey(active: $0) }
                    )) {
                        Text("啟用熱鍵")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Divider()
                    
                    HStack {
                        Text("校正文字:")
                        Spacer()
                        Text("\(formatModifiers(appState.hotKeyModifiers)) + \(formatKey(appState.hotKeyCharacter))")
                            .font(UIConstants.bodyFont.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(UIConstants.secondaryColor)
                            .cornerRadius(UIConstants.cornerRadius)
                    }
                    
                    Button(action: {
                        showHotkeyCustomizationSheet = true
                    }) {
                        Text("自定義熱鍵")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LinearButtonStyle(isPrimary: false))
                    .padding(.top, 8)
                }
                .cardStyle()
            }
            
            // 剪貼板設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("剪貼板設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: Binding(
                        get: { appState.isClipboardMonitoringEnabled },
                        set: { appState.updateClipboardMonitoring(enabled: $0) }
                    )) {
                        Text("啟用剪貼板監控")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Text("當剪貼板有新的文本內容時自動檢測並提供校正選項")
                        .font(UIConstants.captionFont)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .cardStyle()
            }
            
            // 應用程式設定
            Section(header: Text("系統設定").font(UIConstants.sectionHeaderFont)) {
                VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                    Toggle("隨系統開機啟動", isOn: $appSettings.startAtLogin)
                        .toggleStyle(LinearToggleStyle())
                    
                    Text("應用程式將在系統啟動時自動啟動")
                        .font(UIConstants.captionFont)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                    Toggle("自動糾正文字", isOn: $appSettings.autoCorrect)
                        .toggleStyle(LinearToggleStyle())
                    
                    Text("在輸入時自動檢測和修正錯別字")
                        .font(UIConstants.captionFont)
                        .foregroundColor(.secondary)
                }
            }
            .cardStyle()
        }
        .sheet(isPresented: $showHotkeyCustomizationSheet) {
            hotkeyCustomizationView
        }
    }
    
    // API設定視圖
    private var apiSettingsView: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            // API 金鑰配置區域
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                Text("OpenAI API 設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API 金鑰")
                            .font(UIConstants.bodyFont.weight(.medium))
                        
                        // API 金鑰輸入框，使用安全字段
                        SecureField("輸入你的 OpenAI API 金鑰", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disableAutocorrection(true)
                            .padding(.bottom, 4)
                        
                        HStack {
                            // 添加 OpenAI API 網站連結
                            Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.system(size: 12))
                                    Text("前往 OpenAI API 頁面申請")
                                        .font(UIConstants.captionFont)
                                        .underline()
                                }
                                .foregroundColor(UIConstants.primaryColor)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // 直接前往 OpenAI 網站的按鈕
                    Button(action: {
                        if let url = URL(string: "https://platform.openai.com/api-keys") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("在瀏覽器中開啟 OpenAI API 申請頁面")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LinearButtonStyle(isPrimary: false))
                    .padding(.bottom, 10)
                    
                    // 金鑰驗證按鈕
                    HStack {
                        Button(action: {
                            validateApiKey()
                        }) {
                            HStack {
                                Image(systemName: isValidating ? "circle.dashed" : "checkmark.seal")
                                    .rotationEffect(isValidating ? .degrees(0) : .degrees(0))
                                    .animation(isValidating ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isValidating)
                                
                                Text(isValidating ? "驗證中..." : "驗證 API 金鑰")
                            }
                        }
                        .buttonStyle(LinearButtonStyle())
                        .disabled(apiKey.isEmpty || isValidating)
                        
                        Spacer()
                        
                        Button(action: {
                            saveApiKey()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("儲存")
                            }
                        }
                        .buttonStyle(LinearButtonStyle())
                        .disabled(apiKey.isEmpty || isValidating)
                    }
                    
                    // 驗證訊息顯示
                    if showMessage {
                        Text(message)
                            .font(UIConstants.captionFont)
                            .foregroundColor(isSuccess ? UIConstants.successColor : UIConstants.dangerColor)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, UIConstants.spacing)
            }
            
            Spacer()
        }
        .padding(.bottom, UIConstants.spacing)
    }
    
    // 進階設定視圖
    private var advancedSettingsView: some View {
        VStack(alignment: .leading, spacing: UIConstants.groupSpacing) {
            // 介面設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("介面設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: Binding(
                        get: { appState.isVisualEffectsEnabled },
                        set: { appState.updateVisualEffects(enabled: $0) }
                    )) {
                        Text("啟用視覺效果")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Toggle(isOn: Binding(
                        get: { appState.isParticleEffectsEnabled },
                        set: { appState.updateParticleEffects(enabled: $0) }
                    )) {
                        Text("啟用粒子效果")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Toggle(isOn: Binding(
                        get: { appState.isAnimationsEnabled },
                        set: { appState.updateAnimations(enabled: $0) }
                    )) {
                        Text("啟用動畫")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Toggle(isOn: Binding(
                        get: { appState.isHighQualityEffectsEnabled },
                        set: { appState.updateHighQualityEffects(enabled: $0) }
                    )) {
                        Text("高品質效果")
                    }
                    .toggleStyle(LinearToggleStyle())
                }
                .cardStyle()
            }
            
            // 通知設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("通知設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: Binding(
                        get: { NotificationManager.shared.isNotificationsEnabled },
                        set: { NotificationManager.shared.isNotificationsEnabled = $0 }
                    )) {
                        Text("啟用系統通知")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Text("控制應用程式是否顯示校正完成、錯誤等系統通知")
                        .font(UIConstants.captionFont)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .cardStyle()
            }
            
            // 效能設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("效能設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: .constant(true)) {
                        Text("背景處理")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Text("允許應用在背景中處理文本，以獲得更快的回應時間")
                        .font(UIConstants.captionFont)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .cardStyle()
            }
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
                
                // 記錄成功並更新UI狀態，使用安全的狀態更新方法
                logger.debug("API 金鑰保存成功")
                appState.safelyUpdate(\.isApiKeyValid, value: true)
                showSuccessMessage("API 金鑰已保存")
            } catch {
                logger.error("保存 API 金鑰時發生錯誤: \(error.localizedDescription)")
                showErrorMessage("無法保存 API 金鑰: \(error.localizedDescription)")
            }
            
            isSaving = false
        }
    }
    
    private func showSuccessMessage(_ msg: String) {
        message = msg
        isSuccess = true
        showMessage = true
    }
    
    private func showErrorMessage(_ msg: String) {
        message = msg
        isSuccess = false
        showMessage = true
    }
    
    // 熱鍵自定義視圖
    private var hotkeyCustomizationView: some View {
        VStack(spacing: UIConstants.spacing) {
            Text("自定義熱鍵")
                .font(UIConstants.titleFont)
                .padding(.top, UIConstants.spacing)
            
            Divider()
            
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                Text("修飾鍵 (可多選)")
                    .font(UIConstants.bodyFont.weight(.medium))
                
                HStack {
                    modifierButton("Command", symbol: "⌘", key: "command")
                    modifierButton("Option", symbol: "⌥", key: "option")
                    modifierButton("Control", symbol: "⌃", key: "control")
                    modifierButton("Shift", symbol: "⇧", key: "shift")
                }
                
                Text("主鍵")
                    .font(UIConstants.bodyFont.weight(.medium))
                    .padding(.top, UIConstants.spacing / 2)
                
                HStack(spacing: UIConstants.spacing / 2) {
                    characterButton("A", key: "a")
                    characterButton("B", key: "b")
                    characterButton("C", key: "c")
                    characterButton("D", key: "d")
                    characterButton("T", key: "t")
                }
                
                HStack(spacing: UIConstants.spacing / 2) {
                    characterButton("空格", key: "space")
                    characterButton("↩", key: "return")
                    characterButton("⌫", key: "delete")
                    characterButton("↑", key: "up")
                    characterButton("↓", key: "down")
                }
                
                Text("預覽")
                    .font(UIConstants.bodyFont.weight(.medium))
                    .padding(.top, UIConstants.spacing)
                
                Text(tempModifiers.isEmpty && tempCharacter.isEmpty ? 
                     "請選擇修飾鍵和主鍵" : 
                     "\(formatModifiers(tempModifiers)) + \(formatKey(tempCharacter))")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(UIConstants.secondaryColor.opacity(0.5))
                    .cornerRadius(UIConstants.cornerRadius)
            }
            .padding(.horizontal, UIConstants.spacing)
            
            Spacer()
            
            Divider()
            
            HStack {
                Button(action: {
                    showHotkeyCustomizationSheet = false
                }) {
                    Text("取消")
                }
                .buttonStyle(LinearButtonStyle(isPrimary: false))
                
                Spacer()
                
                Button(action: {
                    saveCustomHotkey()
                    showHotkeyCustomizationSheet = false
                }) {
                    Text("儲存熱鍵")
                }
                .buttonStyle(LinearButtonStyle())
                .disabled(tempModifiers.isEmpty || tempCharacter.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            // 初始化臨時變數
            tempModifiers = appState.hotKeyModifiers
            tempCharacter = appState.hotKeyCharacter
        }
    }
    
    // 修飾鍵按鈕
    private func modifierButton(_ title: String, symbol: String, key: String) -> some View {
        Button(action: {
            toggleModifier(key)
        }) {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .fill(tempModifiers.contains(key) ? 
                          UIConstants.primaryColor.opacity(0.2) : 
                          UIConstants.secondaryColor.opacity(0.5))
            )
            .foregroundColor(tempModifiers.contains(key) ? 
                             UIConstants.primaryColor : 
                             .primary)
        }
        .buttonStyle(.plain)
    }
    
    // 字符按鈕
    private func characterButton(_ title: String, key: String) -> some View {
        Button(action: {
            tempCharacter = key
        }) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 60, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                        .fill(tempCharacter == key ? 
                              UIConstants.primaryColor.opacity(0.2) : 
                              UIConstants.secondaryColor.opacity(0.5))
                )
                .foregroundColor(tempCharacter == key ? 
                                 UIConstants.primaryColor : 
                                 .primary)
        }
        .buttonStyle(.plain)
    }
    
    // 切換修飾鍵
    private func toggleModifier(_ key: String) {
        if tempModifiers.contains(key) {
            tempModifiers.removeAll { $0 == key }
        } else {
            tempModifiers.append(key)
        }
    }
    
    // 保存自定義熱鍵
    private func saveCustomHotkey() {
        if !tempModifiers.isEmpty && !tempCharacter.isEmpty {
            appState.updateHotkeySettings(active: true, modifiers: tempModifiers, character: tempCharacter)
            showSuccessMessage("熱鍵已更新")
        }
    }
    
    // 格式化修飾鍵
    private func formatModifiers(_ modifiers: [String]) -> String {
        var symbols = ""
        
        for modifier in modifiers.sorted() {
            switch modifier.lowercased() {
            case "command": symbols += "⌘"
            case "option": symbols += "⌥"
            case "control": symbols += "⌃"
            case "shift": symbols += "⇧"
            default: break
            }
        }
        
        return symbols
    }
    
    // 格式化按鍵
    private func formatKey(_ key: String) -> String {
        switch key.lowercased() {
        case "space": return "空格"
        case "return": return "↩"
        case "delete": return "⌫"
        case "up": return "↑"
        case "down": return "↓"
        default: return key.uppercased()
        }
    }
    
    // 驗證API金鑰
    private func validateApiKey() {
        guard !apiKey.isEmpty else { return }
        
        logger.debug("正在驗證API金鑰")
        isValidating = true
        
        // 這裡需要先保存API金鑰，然後進行驗證
        do {
            try keychain.set(apiKey, key: "OpenAIApiKey")
            logger.debug("API 金鑰已保存至鑰匙圈，準備進行驗證")
        } catch {
            logger.error("保存 API 金鑰失敗: \(error.localizedDescription)")
            showErrorMessage("無法保存 API 金鑰: \(error.localizedDescription)")
            isValidating = false
            return
        }
        
        // 使用Task異步執行API驗證
        Task {
            do {
                // 使用OpenAIService進行實際API驗證
                try await openAIService.validateAPIKey(apiKey)
                
                // 在主線程更新UI
                await MainActor.run {
                    appState.safelyUpdate(\.isApiKeyValid, value: true)
                    showSuccessMessage("API 金鑰驗證成功")
                    isValidating = false
                }
            } catch let apiError as OpenAIError {
                await MainActor.run {
                    appState.safelyUpdate(\.isApiKeyValid, value: false)
                    var errorMessage = "API 金鑰驗證失敗"
                    
                    switch apiError {
                    case .invalidAPIKey:
                        errorMessage = "無效的API金鑰"
                    case .timeout:
                        errorMessage = "連接超時，請檢查網絡連接"
                    case .serverError(let message):
                        errorMessage = "伺服器錯誤: \(message)"
                    case .clientError(let message):
                        errorMessage = "客戶端錯誤: \(message)"
                    case .networkError:
                        errorMessage = "網絡連接錯誤，請檢查網絡連接"
                    default:
                        errorMessage = "驗證失敗: \(apiError.localizedDescription)"
                    }
                    
                    showErrorMessage(errorMessage)
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    appState.safelyUpdate(\.isApiKeyValid, value: false)
                    showErrorMessage("API 金鑰驗證失敗: \(error.localizedDescription)")
                    isValidating = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
} 
