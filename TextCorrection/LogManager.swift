import Foundation
import os.log
import SwiftUI

/// 集中式日誌管理器
class LogManager {
    /// 單例實例
    static let shared = LogManager()
    
    /// 日誌配置級別
    enum LogLevel: String, CaseIterable {
        case debug
        case info
        case notice
        case warning
        case error
        case fault
        
        /// 轉換為系統 OSLogType
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .notice: return .default
            case .warning: return .error
            case .error, .fault: return .fault
            }
        }
        
        /// 用於UI顯示的文字
        var displayName: String {
            switch self {
            case .debug: return "調試"
            case .info: return "信息"
            case .notice: return "通知"
            case .warning: return "警告"
            case .error: return "錯誤"
            case .fault: return "嚴重錯誤"
            }
        }
    }
    
    /// 記錄的日誌條目
    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let level: String
        let category: String
        let message: String
        let subsystem: String
        
        init(id: UUID = UUID(), timestamp: Date = Date(), level: String, category: String, message: String, subsystem: String) {
            self.id = id
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
            self.subsystem = subsystem
        }
    }
    
    /// 內存中存儲的日誌條目
    private(set) var logEntries: [LogEntry] = []
    
    /// 最大存儲的日誌條數，防止內存過大
    private let maxLogEntries = 1000
    
    /// 最小日誌記錄級別，低於此級別的日誌不會被記錄
    private(set) var minimumLogLevel: LogLevel = .info
    
    /// 日誌文件URL
    private var logFileURL: URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.text.correction", isDirectory: true)
        
        // 確保目錄存在
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        return directoryURL.appendingPathComponent("application.log")
    }
    
    /// 私有初始化方法
    private init() {
        setupLogFile()
        
        // 從用戶偏好設置加載日誌級別
        if let savedLevel = UserDefaults.standard.string(forKey: "LogLevel"),
           let level = LogLevel(rawValue: savedLevel) {
            minimumLogLevel = level
        }
    }
    
    /// 設置日誌文件
    private func setupLogFile() {
        // 確保日誌文件存在
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        // 讀取現有日誌文件
        loadLogsFromFile()
        
        // 清理過期日誌
        cleanupOldLogs()
    }
    
    /// 加載日誌文件
    private func loadLogsFromFile() {
        do {
            let data = try Data(contentsOf: logFileURL)
            let decoder = JSONDecoder()
            let logs = try decoder.decode([LogEntry].self, from: data)
            logEntries = logs.suffix(maxLogEntries)
        } catch {
            // 如果文件不存在或格式錯誤，就從空開始
            logEntries = []
        }
    }
    
    /// 保存日誌到文件
    private func saveLogsToFile() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(logEntries)
            try data.write(to: logFileURL)
        } catch {
            print("無法保存日誌文件: \(error.localizedDescription)")
        }
    }
    
    /// 清理過期日誌，只保留最近的日誌
    private func cleanupOldLogs() {
        if logEntries.count > maxLogEntries {
            logEntries = Array(logEntries.suffix(maxLogEntries))
            saveLogsToFile()
        }
    }
    
    /// 設置最小日誌級別
    func setMinimumLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "LogLevel")
    }
    
    /// 添加日誌條目
    func log(level: LogLevel, category: String, message: String, subsystem: String = "com.text.correction") {
        // 檢查日誌級別
        guard shouldLog(level: level) else { return }
        
        // 創建日誌條目
        let entry = LogEntry(level: level.rawValue, category: category, message: message, subsystem: subsystem)
        
        // 添加到內存中
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.logEntries.append(entry)
            
            // 如果超過最大條數，則刪除最舊的
            if self.logEntries.count > self.maxLogEntries {
                self.logEntries.removeFirst()
            }
            
            // 定期保存到文件
            if self.logEntries.count % 20 == 0 {
                self.saveLogsToFile()
            }
        }
    }
    
    /// 檢查是否應該記錄此級別的日誌
    private func shouldLog(level: LogLevel) -> Bool {
        // 將日誌級別轉為數字以便比較
        let levelValues: [LogLevel: Int] = [
            .debug: 0,
            .info: 1,
            .notice: 2,
            .warning: 3,
            .error: 4,
            .fault: 5
        ]
        
        guard let currentValue = levelValues[level],
              let minimumValue = levelValues[minimumLogLevel] else {
            return false
        }
        
        return currentValue >= minimumValue
    }
    
    /// 獲取過濾後的日誌
    func getFilteredLogs(level: LogLevel? = nil, category: String? = nil, searchText: String = "") -> [LogEntry] {
        var filteredLogs = logEntries
        
        // 按級別過濾
        if let level = level {
            filteredLogs = filteredLogs.filter { $0.level == level.rawValue }
        }
        
        // 按類別過濾
        if let category = category, !category.isEmpty {
            filteredLogs = filteredLogs.filter { $0.category == category }
        }
        
        // 按搜索文本過濾
        if !searchText.isEmpty {
            filteredLogs = filteredLogs.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filteredLogs
    }
    
    /// 清空日誌
    func clearLogs() {
        logEntries.removeAll()
        saveLogsToFile()
    }
    
    /// 匯出日誌為文本
    func exportLogsAsText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let logs = logEntries.map { entry -> String in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.level.uppercased())] [\(entry.category)] \(entry.message)"
        }
        
        return logs.joined(separator: "\n")
    }
    
    /// 匯出日誌為 JSON
    func exportLogsAsJSON() -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(logEntries)
        } catch {
            print("無法編碼日誌為JSON: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 獲取所有唯一的日誌類別
    func getAllCategories() -> [String] {
        let categories = Set(logEntries.map { $0.category })
        return Array(categories).sorted()
    }
    
    /// 分享日誌
    func shareLogs() -> URL? {
        do {
            // 創建臨時文件
            let tempDir = FileManager.default.temporaryDirectory
            let logFileTemp = tempDir.appendingPathComponent("TextCorrection-Logs-\(Date().timeIntervalSince1970).log")
            
            // 寫入日誌內容
            try exportLogsAsText().write(to: logFileTemp, atomically: true, encoding: .utf8)
            
            return logFileTemp
        } catch {
            print("分享日誌時發生錯誤: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 匯出診斷報告
    func exportDiagnosticReport() -> URL? {
        do {
            // 創建診斷報告目錄
            let tempDir = FileManager.default.temporaryDirectory
            let reportDir = tempDir.appendingPathComponent("TextCorrection-DiagnosticReport-\(Date().timeIntervalSince1970)", isDirectory: true)
            try FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)
            
            // 添加日誌文件
            let logFile = reportDir.appendingPathComponent("application.log")
            try exportLogsAsText().write(to: logFile, atomically: true, encoding: .utf8)
            
            // 添加系統信息
            let systemInfoFile = reportDir.appendingPathComponent("system-info.txt")
            let systemInfo = """
            應用版本: \(Utilities.getAppVersion())
            macOS版本: \(Utilities.getOSVersion())
            設備型號: \(Utilities.getDeviceModel())
            CPU核心數: \(ProcessInfo.processInfo.processorCount)
            可用內存: \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)) MB
            偏好設置:
            - API Key設置: \(UserDefaults.standard.bool(forKey: "HasSetAPIKey") ? "已設置" : "未設置")
            - 開機自啟: \(UserDefaults.standard.bool(forKey: "LaunchAtStartup") ? "已啟用" : "未啟用")
            - 剪貼板監控: \(UserDefaults.standard.bool(forKey: "ClipboardMonitoring") ? "已啟用" : "未啟用")
            """
            try systemInfo.write(to: systemInfoFile, atomically: true, encoding: .utf8)
            
            // 壓縮為ZIP文件
            let zipFile = tempDir.appendingPathComponent("TextCorrection-DiagnosticReport-\(Date().timeIntervalSince1970).zip")
            try Utilities.createZipFile(sourceURL: reportDir, destinationURL: zipFile)
            
            return zipFile
        } catch {
            print("創建診斷報告時發生錯誤: \(error.localizedDescription)")
            return nil
        }
    }
}

// 擴展 Utilities 類添加 ZIP 壓縮功能
extension Utilities {
    /// 創建 ZIP 文件
    static func createZipFile(sourceURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destinationURL.path, "."]
        process.currentDirectoryURL = sourceURL
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "com.text.correction", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ZIP壓縮失敗"])
        }
    }
    
    /// 獲取設備型號
    static func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    /// 獲取操作系統版本
    static func getOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}

// MARK: - 擴展 Logger 以使用 LogManager
extension Logger {
    /// 使用 LogManager 記錄日誌
    func logWithManager(level: LogManager.LogLevel, message: String) {
        // 同時使用系統日誌
        self.log(level: level.osLogType, "\(message)")
        
        // 使用日誌管理器記錄
        LogManager.shared.log(level: level, category: "Logger", message: message, subsystem: "com.text.correction")
    }
    
    /// 調試級別日誌
    func debugWithManager(_ message: String) {
        logWithManager(level: .debug, message: message)
    }
    
    /// 信息級別日誌
    func infoWithManager(_ message: String) {
        logWithManager(level: .info, message: message)
    }
    
    /// 通知級別日誌
    func noticeWithManager(_ message: String) {
        logWithManager(level: .notice, message: message)
    }
    
    /// 警告級別日誌
    func warningWithManager(_ message: String) {
        logWithManager(level: .warning, message: message)
    }
    
    /// 錯誤級別日誌
    func errorWithManager(_ message: String) {
        logWithManager(level: .error, message: message)
    }
    
    /// 嚴重錯誤級別日誌
    func faultWithManager(_ message: String) {
        logWithManager(level: .fault, message: message)
    }
    
    // 增強的日誌記錄方法，自動整合到 LogManager
    func customLog(level: OSLogType, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        // 使用系統日誌記錄
        self.log(level: level, "\(message)")
        
        // 轉換 OSLogType 到 LogManager.LogLevel
        let logLevel: LogManager.LogLevel
        if level == .debug {
            logLevel = .debug
        } else if level == .info {
            logLevel = .info
        } else if level == .default {
            logLevel = .notice
        } else if level == .error {
            logLevel = .error
        } else {
            // .fault 或任何其他情況
            logLevel = .fault
        }
        
        // 使用 LogManager 記錄
        LogManager.shared.log(
            level: logLevel, 
            category: "System", 
            message: "\(message) (在 \(file):\(line), \(function))", 
            subsystem: "com.text.correction"
        )
    }
} 