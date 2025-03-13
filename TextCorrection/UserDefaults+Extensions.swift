import Foundation

// UserDefaults 擴展，提供帶預設值的 bool 方法
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
} 