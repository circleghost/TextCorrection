import Foundation
import Darwin
import SwiftUI
import AppKit
import os.log

/// 通用類型別名，用於提高代碼可讀性
typealias StringDict = [String: String]

/// 實用工具類
struct Utilities {
    /// 獲取應用程序的bundle ID
    static func getBundleID() -> String {
        return Bundle.main.bundleIdentifier ?? "unknown"
    }
    
    /// 獲取應用程序版本號
    static func getAppVersion() -> String {
        let versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
        return "\(versionNumber) (\(buildNumber))"
    }
    
    /// 判斷應用程序是否是以沙盒方式運行
    static func isAppSandboxed() -> Bool {
        // 檢查應用是否以沙盒方式運行
        if let bundleURL = Bundle.main.resourceURL {
            let sandboxToken = "Library/Containers/"
            return bundleURL.path.contains(sandboxToken)
        }
        return false
    }
}

/// 字體管理器，用於集中管理應用程式字體
class FontManager {
    // 靜態單例
    static let shared = FontManager()
    
    // 字體緩存
    private var fontCache: [String: NSFont] = [:]
    
    // 同步隊列，用於保護fontCache的訪問
    private let syncQueue = DispatchQueue(label: "com.yourcompany.TextCorrection.FontManager")
    
    // 粉圓體的實際字體名稱
    private let pungyuFontNames = ["jf-openhuninn-2.1", "jf-openhuninn", "JF Open Huninn", "粉圓體", "jf粉圓體", "JF粉圓體"]
    
    // 日誌
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "FontManager")
    
    // 私有初始化方法，防止外部創建實例
    private init() {}
    
    /// 獲取粉圓體NSFont，適用於AppKit
    func getPungyuFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        // 生成緩存鍵
        let cacheKey = "pungyu-\(size)-\(weight.rawValue)"
        
        // 同步訪問緩存
        if let cachedFont = self.syncQueue.sync(execute: { self.fontCache[cacheKey] }) {
            return cachedFont
        }
        
        // 嘗試載入字體
        for name in self.pungyuFontNames {
            if let font = NSFont(name: name, size: size) {
                // 首次載入時記錄日誌
                let logMessage = "成功載入字體：\(name)"
                // 確保日誌在主線程上記錄
                if Thread.isMainThread {
                    self.logger.debug("\(logMessage)")
                } else {
                    DispatchQueue.main.async {
                        self.logger.debug("\(logMessage)")
                    }
                }
                
                // 安全地存入緩存
                self.syncQueue.sync {
                    self.fontCache[cacheKey] = font
                }
                return font
            }
        }
        
        // 找不到字體時記錄錯誤
        let errorMessage = "無法載入粉圓體，使用系統字體代替。已嘗試的字體名稱：\(self.pungyuFontNames.joined(separator: ", "))"
        // 確保錯誤日誌在主線程上記錄
        if Thread.isMainThread {
            self.logger.error("\(errorMessage)")
        } else {
            DispatchQueue.main.async {
                self.logger.error("\(errorMessage)")
            }
        }
        
        // 使用系統字體作為備選
        let systemFont = NSFont.systemFont(ofSize: size, weight: weight)
        self.syncQueue.sync {
            self.fontCache[cacheKey] = systemFont
        }
        return systemFont
    }
    
    /// 獲取粉圓體SwiftUI.Font，適用於SwiftUI
    func getPungyuFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // 對應NSFont.Weight和Font.Weight
        let nsWeight: NSFont.Weight
        switch weight {
        case .black: nsWeight = .black
        case .bold: nsWeight = .bold
        case .heavy: nsWeight = .heavy
        case .light: nsWeight = .light
        case .medium: nsWeight = .medium
        case .regular: nsWeight = .regular
        case .semibold: nsWeight = .semibold
        case .thin: nsWeight = .thin
        case .ultraLight: nsWeight = .ultraLight
        default: nsWeight = .regular
        }
        
        // 獲取NSFont然後轉換為SwiftUI.Font
        let nsFont = self.getPungyuFont(size: size, weight: nsWeight)
        return Font(nsFont)
    }
    
    /// 列出所有可用字體（調試用）
    func listAllAvailableFonts() {
        let fontFamilyNames = NSFontManager.shared.availableFontFamilies.sorted()
        // 確保日誌在主線程上記錄
        if Thread.isMainThread {
            self.logger.debug("系統可用字體：\(fontFamilyNames.joined(separator: ", "))")
        } else {
            let fontListMessage = fontFamilyNames.joined(separator: ", ")
            DispatchQueue.main.async {
                self.logger.debug("系統可用字體：\(fontListMessage)")
            }
        }
    }
}

// SwiftUI Font擴展，方便在SwiftUI中使用粉圓體
extension Font {
    /// 粉圓體字體
    static func pungyu(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return FontManager.shared.getPungyuFont(size: size, weight: weight)
    }
}

// NSFont擴展，方便在AppKit中使用粉圓體
extension NSFont {
    /// 粉圓體字體
    static func pungyu(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return FontManager.shared.getPungyuFont(size: size, weight: weight)
    }
}

@Sendable func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TextCorrectionError.timeout
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

@Sendable func trimExtraWhitespace(_ text: String) -> String {
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}