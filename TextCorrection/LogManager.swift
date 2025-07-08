import Foundation
import os.log
import SwiftUI

/// 集中式日誌管理器
@MainActor
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
    private let maxLogEntries = 2000
    
    /// 最小日誌記錄級別，低於此級別的日誌不會被記錄
    private(set) var minimumLogLevel: LogLevel = .debug
    
    /// 最後保存日誌的時間
    private var lastSaveTime = Date()
    
    /// 日誌保存頻率（秒）
    private let saveInterval: TimeInterval = 30
    
    /// 自動保存計時器
    private var autoSaveTimer: Timer?
    
    /// 日誌文件目錄URL
    private var logDirectoryURL: URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.text.correction", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        
        // 確保目錄存在
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        return directoryURL
    }
    
    /// 當前日誌文件URL
    private var currentLogFileURL: URL {
        return logDirectoryURL.appendingPathComponent("application.log")
    }
    
    /// 私有初始化方法
    private init() {
        setupLogSystem()
        
        // 從用戶偏好設置加載日誌級別
        if let savedLevel = UserDefaults.standard.string(forKey: "LogLevel"),
           let level = LogLevel(rawValue: savedLevel) {
            minimumLogLevel = level
        }
        
        // 記錄應用啟動
        log(level: .info, category: "Application", message: "應用程式啟動", subsystem: "com.text.correction")
        
        // 開始自動保存計時器
        startAutoSaveTimer()
        
        // 註冊應用程式關閉通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    deinit {
        autoSaveTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 設置日誌系統
    private func setupLogSystem() {
        // 確保日誌目錄存在
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        
        // 確保日誌文件存在
        if !FileManager.default.fileExists(atPath: currentLogFileURL.path) {
            FileManager.default.createFile(atPath: currentLogFileURL.path, contents: nil)
        }
        
        // 讀取現有日誌文件
        loadLogsFromFile()
        
        // 清理過期日誌
        cleanupOldLogs()
        
        // 創建備份
        createLogBackupIfNeeded()
    }
    
    /// 開始自動保存計時器
    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: saveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveLogsToFile()
            }
        }
    }
    
    /// 應用程式將要終止
    @objc private func applicationWillTerminate() {
        log(level: .info, category: "Application", message: "應用程式關閉", subsystem: "com.text.correction")
        saveLogsToFile()
    }
    
    /// 加載日誌文件
    private func loadLogsFromFile() {
        do {
            let data = try Data(contentsOf: currentLogFileURL)
            let decoder = JSONDecoder()
            let logs = try decoder.decode([LogEntry].self, from: data)
            logEntries = logs.suffix(maxLogEntries)
        } catch {
            // 如果文件不存在或格式錯誤，就從空開始
            logEntries = []
            print("加載日誌文件失敗: \(error.localizedDescription)")
        }
    }
    
    /// 保存日誌到文件
    private func saveLogsToFile() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(logEntries)
            try data.write(to: currentLogFileURL)
            lastSaveTime = Date()
        } catch {
            print("無法保存日誌文件: \(error.localizedDescription)")
        }
    }
    
    /// 創建日誌備份
    private func createLogBackupIfNeeded() {
        // 獲取當前日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        // 備份文件名
        let backupFileName = "application_\(dateString).log"
        let backupURL = logDirectoryURL.appendingPathComponent(backupFileName)
        
        // 如果今天的備份已存在，則跳過
        if FileManager.default.fileExists(atPath: backupURL.path) {
            return
        }
        
        // 創建備份
        do {
            if FileManager.default.fileExists(atPath: currentLogFileURL.path) {
                try FileManager.default.copyItem(at: currentLogFileURL, to: backupURL)
                
                // 記錄備份創建
                log(level: .info, category: "LogManager", message: "已創建日誌備份: \(backupFileName)", subsystem: "com.text.correction")
            }
        } catch {
            print("創建日誌備份失敗: \(error.localizedDescription)")
        }
        
        // 清理舊的備份文件（只保留最近7天）
        cleanupOldBackups()
    }
    
    /// 清理舊的備份文件
    private func cleanupOldBackups() {
        do {
            let fileManager = FileManager.default
            let backupFiles = try fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.lastPathComponent.starts(with: "application_") && $0.lastPathComponent.hasSuffix(".log") }
                .sorted { (first, second) -> Bool in
                    let firstDate = try first.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let secondDate = try second.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return firstDate > secondDate
                }
            
            // 如果備份超過7個，刪除最舊的
            if backupFiles.count > 7 {
                for file in backupFiles.dropFirst(7) {
                    try fileManager.removeItem(at: file)
                    log(level: .info, category: "LogManager", message: "已刪除舊日誌備份: \(file.lastPathComponent)", subsystem: "com.text.correction")
                }
            }
        } catch {
            print("清理舊備份失敗: \(error.localizedDescription)")
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
        log(level: .info, category: "LogManager", message: "日誌級別已設置為: \(level.displayName)", subsystem: "com.text.correction")
    }
    
    /// 添加日誌條目
    func log(level: LogLevel, category: String, message: String, subsystem: String = "com.text.correction") {
        // 檢查日誌級別
        guard shouldLog(level: level) else { return }
        
        // 創建日誌條目
        let entry = LogEntry(level: level.rawValue, category: category, message: message, subsystem: subsystem)
        
        // 直接添加到內存中（已經在 MainActor 上下文中）
        logEntries.append(entry)
        
        // 如果超過最大條數，則刪除最舊的
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst()
        }
        
        // 每10條日誌保存一次，或者距離上次保存超過30秒
        if logEntries.count % 10 == 0 || Date().timeIntervalSince(lastSaveTime) > saveInterval {
            saveLogsToFile()
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
        log(level: .info, category: "LogManager", message: "日誌已清空", subsystem: "com.text.correction")
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
            應用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
            構建版本: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知") 
            macOS版本: \(ProcessInfo.processInfo.operatingSystemVersionString)
            設備型號: \(getDeviceModel())
            CPU核心數: \(ProcessInfo.processInfo.processorCount)
            可用內存: \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)) MB
            低電量模式: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "是" : "否")
            日誌設置:
            - 最低日誌級別: \(minimumLogLevel.displayName)
            - 日誌條目數量: \(logEntries.count)
            偏好設置:
            - API Key設置: \(UserDefaults.standard.bool(forKey: "HasSetAPIKey") ? "已設置" : "未設置")
            - 開機自啟: \(UserDefaults.standard.bool(forKey: "LaunchAtStartup") ? "已啟用" : "未啟用")
            - 剪貼板監控: \(UserDefaults.standard.bool(forKey: "ClipboardMonitoring") ? "已啟用" : "未啟用")
            """
            try systemInfo.write(to: systemInfoFile, atomically: true, encoding: .utf8)
            
            // 添加備份日誌
            let backupsDir = reportDir.appendingPathComponent("log_backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            
            do {
                let backupFiles = try FileManager.default.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.starts(with: "application_") }
                
                for backupFile in backupFiles.prefix(3) { // 只複製最近3個備份
                    let destination = backupsDir.appendingPathComponent(backupFile.lastPathComponent)
                    try FileManager.default.copyItem(at: backupFile, to: destination)
                }
            } catch {
                let errorInfo = "無法複製日誌備份: \(error.localizedDescription)"
                try errorInfo.write(to: backupsDir.appendingPathComponent("backup_error.txt"), atomically: true, encoding: .utf8)
            }
            
            // 壓縮為ZIP文件
            let zipFile = tempDir.appendingPathComponent("TextCorrection-DiagnosticReport-\(Date().timeIntervalSince1970).zip")
            compressDirectory(sourceURL: reportDir, destinationURL: zipFile)
            
            return zipFile
        } catch {
            print("創建診斷報告時發生錯誤: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 壓縮目錄為ZIP文件
    private func compressDirectory(sourceURL: URL, destinationURL: URL) {
        let process = Process()
        process.launchPath = "/usr/bin/zip"
        process.arguments = ["-r", destinationURL.path, sourceURL.lastPathComponent]
        process.currentDirectoryURL = sourceURL.deletingLastPathComponent()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("壓縮文件夾失敗: \(error.localizedDescription)")
        }
    }
    
    /// 獲取設備型號
    private func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

/// 擴展 Logger 以整合 LogManager
extension Logger {
    /// 使用 LogManager 記錄日誌
    @MainActor
    func logWithManager(level: LogManager.LogLevel, message: String) {
        // 同時使用系統日誌
        self.log(level: level.osLogType, "\(message)")
        
        // 使用日誌管理器記錄
        LogManager.shared.log(level: level, category: "Logger", message: message, subsystem: "com.text.correction")
    }
    
    /// 調試級別日誌
    @MainActor
    func debugWithManager(_ message: String) {
        logWithManager(level: .debug, message: message)
    }
    
    /// 信息級別日誌
    @MainActor
    func infoWithManager(_ message: String) {
        logWithManager(level: .info, message: message)
    }
    
    /// 通知級別日誌
    @MainActor
    func noticeWithManager(_ message: String) {
        logWithManager(level: .notice, message: message)
    }
    
    /// 警告級別日誌
    @MainActor
    func warningWithManager(_ message: String) {
        logWithManager(level: .warning, message: message)
    }
    
    /// 錯誤級別日誌
    @MainActor
    func errorWithManager(_ message: String) {
        logWithManager(level: .error, message: message)
    }
    
    /// 嚴重錯誤級別日誌
    @MainActor
    func faultWithManager(_ message: String) {
        logWithManager(level: .fault, message: message)
    }
    
    // 增強的日誌記錄方法，自動整合到 LogManager
    @MainActor
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