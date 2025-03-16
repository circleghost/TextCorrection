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
    
    static let titleFont = Font.system(size: 24, weight: .bold)
    static let sectionFont = Font.system(size: 16, weight: .semibold)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
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
    @EnvironmentObject private var appStateObserver: AppStateObserver
    @Environment(\.appState) private var appState
    
    @State private var apiKey: String = ""
    @State private var showingAPIKeyDialog = false
    @State private var isValidatingApiKey = false
    @State private var selectedTab = 0
    @State private var showHotkeyCustomizationSheet = false
    
    // 環境變數，用於關閉視窗
    @Environment(\.dismiss) private var dismiss
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "SettingsView")
    
    var body: some View {
        VStack(spacing: 0) {
            // 頂部標題欄
            HStack {
                Text("設定")
                    .font(UIConstants.titleFont)
                
                Spacer()
                
                Button(action: {
                    resetSettings()
                }) {
                    Text("重置")
                        .font(UIConstants.bodyFont)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // 標籤選擇欄
            HStack(spacing: 0) {
                tabButton(title: "一般", systemImage: "gear", tag: 0)
                tabButton(title: "外觀", systemImage: "paintbrush", tag: 1)
                tabButton(title: "API", systemImage: "network", tag: 2)
                tabButton(title: "關於", systemImage: "info.circle", tag: 3)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color(NSColor.windowBackgroundColor))
            
            // 分隔線
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
            
            // 內容區域
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 根據選項卡顯示不同的設置
                    switch selectedTab {
                    case 0:
                        generalSettingsView
                    case 1:
                        appearanceSettingsView
                    case 2:
                        apiSettingsView
                    case 3:
                        aboutView
                    default:
                        generalSettingsView
                    }
                }
                .padding(.top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .onAppear {
            // 從AppStateObserver加載當前設置
            apiKey = appStateObserver.apiKey
            
            logger.debug("設置視圖已出現")
        }
        .sheet(isPresented: $showHotkeyCustomizationSheet) {
            HotkeyCustomizationView()
                .environmentObject(appStateObserver)
        }
        .frame(width: 500, height: 400)
    }
    
    // MARK: - 標籤按鈕
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
                        get: { appStateObserver.hotkeysEnabled },
                        set: { newValue in 
                            appStateObserver.updateHotkeySettings(enabled: newValue, hotkey: appStateObserver.correctionHotkey)
                        }
                    )) {
                        Text("啟用熱鍵")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Divider()
                    
                    HStack {
                        Text("校正文字:")
                        Spacer()
                        Text(appStateObserver.correctionHotkey.isEmpty ? "尚未設置" : appStateObserver.correctionHotkey)
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
                Text("剪貼板監控")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: Binding(
                        get: { appStateObserver.isMonitoringClipboard },
                        set: { newValue in 
                            appStateObserver.updateClipboardMonitoring(newValue)
                        }
                    )) {
                        Text("監控剪貼板")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Text("當啟用時，應用程式將監控剪貼板變化並提供快速校正選項")
                        .font(UIConstants.bodyFont)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardStyle()
            }
            
            // 字體大小設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("顯示設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    HStack {
                        Text("字體大小")
                        Spacer()
                        Text("\(Int(appStateObserver.fontSize))")
                            .frame(width: 30)
                        Stepper("", value: Binding(
                            get: { appStateObserver.fontSize },
                            set: { newValue in 
                                appStateObserver.updateFontSize(newValue)
                            }
                        ), in: 10...30, step: 1)
                    }
                }
                .cardStyle()
            }
        }
        .padding(.bottom, UIConstants.spacing)
    }
    
    // 外觀設定視圖
    private var appearanceSettingsView: some View {
        VStack(alignment: .leading, spacing: UIConstants.groupSpacing) {
            // 視覺效果設定
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("視覺效果")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Toggle(isOn: Binding(
                        get: { appStateObserver.isVisualEffectsEnabled },
                        set: { newValue in 
                            appStateObserver.updateVisualEffects(newValue)
                        }
                    )) {
                        Text("啟用視覺效果")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Toggle(isOn: Binding(
                        get: { appStateObserver.isParticleEffectsEnabled },
                        set: { newValue in 
                            appStateObserver.updateParticleEffects(newValue)
                        }
                    )) {
                        Text("啟用粒子特效")
                    }
                    .toggleStyle(LinearToggleStyle())
                    
                    Text("視覺效果可能會影響性能，在較舊的設備上可能導致應用程式運行緩慢")
                        .font(UIConstants.bodyFont)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardStyle()
            }
        }
        .padding(.bottom, UIConstants.spacing)
    }
    
    // API設定視圖
    private var apiSettingsView: some View {
        VStack(alignment: .leading, spacing: UIConstants.groupSpacing) {
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("API設定")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    HStack {
                        Text("API金鑰")
                        Spacer()
                        if appStateObserver.isApiKeyValid {
                            Text("有效")
                                .foregroundColor(.green)
                                .font(UIConstants.bodyFont.weight(.medium))
                        } else {
                            Text("無效")
                                .foregroundColor(.red)
                                .font(UIConstants.bodyFont.weight(.medium))
                        }
                    }
                    
                    // 不顯示實際金鑰，只顯示掩碼
                    Text(maskApiKey(appStateObserver.apiKey))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(UIConstants.secondaryColor.opacity(0.3))
                        .cornerRadius(UIConstants.cornerRadius)
                    
                    Button(action: {
                        showingAPIKeyDialog = true
                    }) {
                        Text("更改API金鑰")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LinearButtonStyle(isPrimary: false))
                }
                .cardStyle()
            }
            
            VStack(alignment: .leading, spacing: UIConstants.spacing / 2) {
                Text("連接資訊")
                    .font(UIConstants.sectionFont)
                    .padding(.horizontal, UIConstants.spacing)
                
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    HStack {
                        Text("OpenAI服務")
                        Spacer()
                        if appStateObserver.isOpenAIServiceAvailable {
                            Text("可用")
                                .foregroundColor(.green)
                                .font(UIConstants.bodyFont.weight(.medium))
                        } else {
                            Text("不可用")
                                .foregroundColor(.red)
                                .font(UIConstants.bodyFont.weight(.medium))
                        }
                    }
                    
                    Button("測試連接") {
                        // 開始測試連接
                        isValidatingApiKey = true
                        
                        // 呼叫驗證API金鑰的方法
                        Task {
                            let key = appStateObserver.apiKey
                            if !key.isEmpty {
                                await appState.validateApiConnection()
                            } else {
                                logger.warning("無法測試連接：API金鑰為空")
                            }
                        }
                    }
                    .buttonStyle(LinearButtonStyle(isPrimary: true))
                    .disabled(isValidatingApiKey || appStateObserver.apiKey.isEmpty)
                }
                .cardStyle()
            }
        }
        .padding(.bottom, UIConstants.spacing)
        .sheet(isPresented: $showingAPIKeyDialog) {
            ApiKeyInputView(apiKey: $apiKey)
                .environmentObject(appStateObserver)
        }
    }
    
    // 關於視圖
    private var aboutView: some View {
        VStack(alignment: .leading, spacing: UIConstants.groupSpacing) {
            VStack(alignment: .center, spacing: UIConstants.spacing) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 50))
                    .foregroundColor(UIConstants.primaryColor)
                
                Text("文本校正")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("版本 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                    .padding(.vertical)
                
                Text("這是一個使用 OpenAI API 進行文本校正的應用程式，能夠檢查並修正中文寫作中的常見錯誤。")
                    .font(UIConstants.bodyFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 20) {
                    Button("查看許可") {
                        // 打開許可協議
                    }
                    .buttonStyle(LinearButtonStyle(isPrimary: false))
                    
                    Button("網站") {
                        // 打開網站
                        if let url = URL(string: "https://openai.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(LinearButtonStyle(isPrimary: true))
                }
                .padding(.top)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
            .padding()
        }
    }
    
    // MARK: - 功能方法
    private func resetSettings() {
        // 重置所有設定
        Task {
            await appState.resetSettings()
        }
        logger.debug("重置所有設定")
    }
    
    // 掩碼 API 金鑰
    private func maskApiKey(_ key: String) -> String {
        if key.isEmpty {
            return "尚未設置 API 金鑰"
        }
        
        if key.count <= 8 {
            return String(repeating: "•", count: key.count)
        }
        
        // 保留前 4 個和後 4 個字符，中間用 • 替代
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        let maskLength = key.count - 8
        let mask = String(repeating: "•", count: maskLength)
        
        return "\(prefix)\(mask)\(suffix)"
    }
}

// MARK: - API金鑰輸入視圖
struct ApiKeyInputView: View {
    @Binding var apiKey: String
    @State private var inputKey: String = ""
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var appStateObserver: AppStateObserver
    @Environment(\.appState) private var appState
    
    var body: some View {
        VStack(spacing: 20) {
            Text("輸入 OpenAI API 金鑰")
                .font(.headline)
            
            Text("API 金鑰用於連接 OpenAI 服務。請從 OpenAI 網站獲取您的 API 金鑰。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            SecureField("API 金鑰", text: $inputKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 300)
            
            HStack {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(LinearButtonStyle(isPrimary: false))
                
                Button("儲存") {
                    saveApiKey()
                }
                .buttonStyle(LinearButtonStyle(isPrimary: true))
                .disabled(inputKey.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            if !apiKey.isEmpty {
                inputKey = apiKey
            }
        }
    }
    
    private func saveApiKey() {
        apiKey = inputKey
        
        // 更新 AppState
        appStateObserver.updateApiKey(apiKey)
        
        // 儲存到 Keychain
        do {
            let keychain = Keychain(service: "com.yourcompany.TextCorrection")
            try keychain.set(apiKey, key: "OpenAIApiKey")
            
            // 自動驗證新的API金鑰
            Task {
                await appState.validateApiKey(apiKey)
            }
        } catch {
            print("無法儲存 API 金鑰：\(error)")
        }
        
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - 熱鍵自定義視圖
struct HotkeyCustomizationView: View {
    @EnvironmentObject private var appStateObserver: AppStateObserver
    @Environment(\.appState) private var appState
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedModifiers: [String] = []
    @State private var selectedKey: String = ""
    
    private let availableModifiers = ["⌘", "⌥", "⌃", "⇧"]
    private let availableKeys = [
        "space", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("自定義熱鍵")
                .font(.headline)
            
            Text("選擇組合鍵及字符作為文本校正的快捷鍵")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // 修飾鍵選擇
            VStack(alignment: .leading, spacing: 10) {
                Text("修飾鍵:")
                    .font(.subheadline)
                
                HStack {
                    ForEach(availableModifiers, id: \.self) { modifier in
                        Toggle(isOn: Binding(
                            get: { selectedModifiers.contains(modifier) },
                            set: { isOn in
                                if isOn {
                                    selectedModifiers.append(modifier)
                                } else {
                                    selectedModifiers.removeAll { $0 == modifier }
                                }
                            }
                        )) {
                            Text(modifier)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            // 按鍵選擇
            VStack(alignment: .leading, spacing: 10) {
                Text("按鍵:")
                    .font(.subheadline)
                
                Picker("", selection: $selectedKey) {
                    Text("未選擇").tag("")
                    ForEach(availableKeys, id: \.self) { key in
                        Text(formatKeyDisplay(key)).tag(key)
                    }
                }
                .frame(width: 200)
            }
            .padding()
            .background(Color(.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            // 預覽
            VStack(alignment: .center, spacing: 10) {
                Text("目前組合:")
                    .font(.subheadline)
                
                HStack {
                    ForEach(selectedModifiers, id: \.self) { modifier in
                        Text(modifier)
                    }
                    
                    if !selectedKey.isEmpty {
                        Text(formatKeyDisplay(selectedKey))
                    } else {
                        Text("未選擇按鍵")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }
            
            // 按鈕
            HStack {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(LinearButtonStyle(isPrimary: false))
                
                Button("儲存") {
                    saveHotkey()
                }
                .buttonStyle(LinearButtonStyle(isPrimary: true))
                .disabled(selectedModifiers.isEmpty || selectedKey.isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            // 從當前設置載入
            loadCurrentHotkey()
        }
    }
    
    private func loadCurrentHotkey() {
        let currentHotkey = appStateObserver.correctionHotkey
        
        if !currentHotkey.isEmpty {
            // 解析當前熱鍵
            let components = currentHotkey.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
            
            if components.count >= 2 {
                // 最後一個組件是按鍵
                selectedKey = components.last ?? ""
                
                // 前面的組件是修飾鍵
                selectedModifiers = components.dropLast().map { modifier -> String in
                    switch modifier.lowercased() {
                    case "command", "cmd", "⌘": return "⌘"
                    case "option", "alt", "⌥": return "⌥"
                    case "control", "ctrl", "⌃": return "⌃"
                    case "shift", "⇧": return "⇧"
                    default: return modifier
                    }
                }
            }
        }
    }
    
    private func saveHotkey() {
        // 創建熱鍵字符串
        let hotkeyString = selectedModifiers.joined(separator: "+") + "+" + selectedKey
        
        // 更新AppState
        appStateObserver.updateHotkeySettings(enabled: true, hotkey: hotkeyString)
        
        // 關閉視圖
        presentationMode.wrappedValue.dismiss()
    }
    
    private func formatKeyDisplay(_ key: String) -> String {
        if key == "space" {
            return "空格"
        }
        return key
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppStateObserver.shared)
}
