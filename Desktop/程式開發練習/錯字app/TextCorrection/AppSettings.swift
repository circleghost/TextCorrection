import Foundation

// AppSettings 類別用於管理應用程式設定
class AppSettings {
    private static let userDefaults = UserDefaults.standard
    
    // 設定鍵常量
    private struct Keys {
        static let visualEffectsEnabled = "visualEffectsEnabled"
        static let particleEffectsEnabled = "particleEffectsEnabled"
        static let animationsEnabled = "animationsEnabled"
        static let highQualityEffects = "highQualityEffects"
    }
    
    // 視覺特效啟用狀態
    static var visualEffectsEnabled: Bool {
        get {
            // 預設為啟用
            if userDefaults.object(forKey: Keys.visualEffectsEnabled) == nil {
                return true
            }
            return userDefaults.bool(forKey: Keys.visualEffectsEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.visualEffectsEnabled)
            NotificationCenter.default.post(name: .visualEffectsSettingChanged, object: newValue)
        }
    }
    
    // 粒子特效啟用狀態
    static var particleEffectsEnabled: Bool {
        get {
            // 預設為啟用
            if userDefaults.object(forKey: Keys.particleEffectsEnabled) == nil {
                return true
            }
            return userDefaults.bool(forKey: Keys.particleEffectsEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.particleEffectsEnabled)
            NotificationCenter.default.post(name: .visualEffectsSettingChanged, object: newValue)
        }
    }
    
    // 動畫特效啟用狀態
    static var animationsEnabled: Bool {
        get {
            // 預設為啟用
            if userDefaults.object(forKey: Keys.animationsEnabled) == nil {
                return true
            }
            return userDefaults.bool(forKey: Keys.animationsEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.animationsEnabled)
            NotificationCenter.default.post(name: .visualEffectsSettingChanged, object: newValue)
        }
    }
    
    // 高品質特效啟用狀態
    static var highQualityEffects: Bool {
        get {
            // 預設為啟用，但會檢查設備性能
            let shouldEnableByDefault = !ProcessInfo.processInfo.isLowPowerModeEnabled && 
                                       ProcessInfo.processInfo.processorCount >= 4
            if userDefaults.object(forKey: Keys.highQualityEffects) == nil {
                return shouldEnableByDefault
            }
            return userDefaults.bool(forKey: Keys.highQualityEffects)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.highQualityEffects)
            NotificationCenter.default.post(name: .visualEffectsSettingChanged, object: newValue)
        }
    }
    
    // 重置所有設定為預設值
    static func resetToDefaults() {
        userDefaults.removeObject(forKey: Keys.visualEffectsEnabled)
        userDefaults.removeObject(forKey: Keys.particleEffectsEnabled)
        userDefaults.removeObject(forKey: Keys.animationsEnabled)
        userDefaults.removeObject(forKey: Keys.highQualityEffects)
        
        // 通知設定變更
        NotificationCenter.default.post(name: .visualEffectsSettingChanged, object: nil)
    }
}

// 通知名稱擴展
extension Notification.Name {
    static let visualEffectsSettingChanged = Notification.Name("visualEffectsSettingChanged")
} 