import Foundation
import Combine
import os.log

/// 應用程序設置類
class AppSettings: ObservableObject {
    /// 單例實例
    static let shared = AppSettings()
    
    /// 發布者（用於通知設置變更）
    let objectWillChange = PassthroughSubject<Void, Never>()
    
    // 日誌記錄器
    private let logger = Logger(subsystem: "com.text.correction", category: "AppSettings")
    
    /// 用戶默認值鍵名常量
    private enum UserDefaultsKeys {
        static let ignoreWords = "ignore_words"
        static let textSizeLimit = "text_size_limit"
        static let autoCorrect = "auto_correct"
        static let startAtLogin = "start_at_login"
        static let selectedModel = "selected_model"
        static let openaiApiKey = "openai_api_key"
        static let geminiApiKey = "gemini_api_key"
        static let textStreamingSpeed = "text_streaming_speed"
    }
    
    /// 忽略字詞列表
    var ignoreWords: [String] {
        get {
            return UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.ignoreWords) ?? []
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.ignoreWords)
        }
    }
    
    /// 文本大小限制（單位：字符）
    var textSizeLimit: Int {
        get {
            return UserDefaults.standard.integer(forKey: UserDefaultsKeys.textSizeLimit)
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.textSizeLimit)
        }
    }
    
    /// 是否自動糾正
    var autoCorrect: Bool {
        get {
            // 如果設置不存在，默認為true
            if UserDefaults.standard.object(forKey: UserDefaultsKeys.autoCorrect) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoCorrect)
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.autoCorrect)
        }
    }
    
    /// 是否開機啟動
    var startAtLogin: Bool {
        get {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.startAtLogin)
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.startAtLogin)
            configureStartAtLogin(newValue)
        }
    }
    
    /// 私有初始化方法
    private init() {
        // 設置默認值（如果尚未設置）
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.textSizeLimit) == nil {
            textSizeLimit = 5000 // 默認限制為5000字符
        }
        
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.startAtLogin) == nil {
            startAtLogin = false // 默認不開機啟動
        }
        
        logger.debug("AppSettings初始化完成")
    }
    
    /// 添加忽略字詞
    func addIgnoreWord(_ word: String) {
        if !ignoreWords.contains(word) {
            var updatedList = ignoreWords
            updatedList.append(word)
            ignoreWords = updatedList
            logger.debug("已添加忽略字詞: \(word)")
        }
    }
    
    /// 刪除忽略字詞
    func removeIgnoreWord(_ word: String) {
        if let index = ignoreWords.firstIndex(of: word) {
            var updatedList = ignoreWords
            updatedList.remove(at: index)
            ignoreWords = updatedList
            logger.debug("已刪除忽略字詞: \(word)")
        }
    }
    
    /// 選擇的 AI 模型
    var selectedModel: AIModel {
        get {
            if let modelString = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedModel),
               let model = AIModel(rawValue: modelString) {
                return model
            }
            return .gpt41 // 默認使用 GPT-4.1
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.selectedModel)
            logger.debug("已選擇模型: \(newValue.displayName)")
        }
    }
    
    /// OpenAI API Key
    var openaiApiKey: String {
        get {
            return UserDefaults.standard.string(forKey: UserDefaultsKeys.openaiApiKey) ?? ""
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.openaiApiKey)
            logger.debug("OpenAI API Key 已更新")
        }
    }
    
    /// Gemini API Key
    var geminiApiKey: String {
        get {
            return UserDefaults.standard.string(forKey: UserDefaultsKeys.geminiApiKey) ?? ""
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.geminiApiKey)
            logger.debug("Gemini API Key 已更新")
        }
    }
    
    /// 根據選擇的模型獲取對應的 API Key
    func getAPIKeyForSelectedModel() -> String {
        switch selectedModel.provider {
        case .openai:
            return openaiApiKey
        case .gemini:
            return geminiApiKey
        }
    }
    
    /// 檢查選擇的模型是否有有效的 API Key
    func hasValidAPIKeyForSelectedModel() -> Bool {
        let apiKey = getAPIKeyForSelectedModel()
        return !apiKey.isEmpty && apiKey.count > 10 // 簡單的長度檢查
    }
    
    /// 文字流動速度 (秒)
    var textStreamingSpeed: Double {
        get {
            let speed = UserDefaults.standard.double(forKey: UserDefaultsKeys.textStreamingSpeed)
            return speed == 0 ? 0.08 : speed // 預設 80ms
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.textStreamingSpeed)
            logger.debug("文字流動速度已更新為: \(newValue)秒")
        }
    }
    
    /// 配置是否開機啟動
    private func configureStartAtLogin(_ enable: Bool) {
        // 這裡使用 SMLoginItemSetEnabled 來設置開機啟動
        // 注意：這需要創建一個單獨的 LoginItem 幫助程序應用
        // 在完整實現中，你需要使用 ServiceManagement 框架
        // 或者使用現代的 SMAppService API
        // 但由於我們簡化起見，這裡先不具體實現
        logger.debug("配置開機啟動: \(enable ? "啟用" : "禁用")")
    }
}

// 通知名稱擴展
extension Notification.Name {
    static let visualEffectsSettingChanged = Notification.Name("visualEffectsSettingChanged")
} 