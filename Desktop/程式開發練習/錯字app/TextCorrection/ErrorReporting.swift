import Foundation
import SwiftUI
import os.log

/// 錯誤記錄等級
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

/// 用於管理錯誤報告和日誌記錄的類
class ErrorReportingManager {
    
    // 單例模式
    static let shared = ErrorReportingManager()
    
    // 私有初始化器確保單例使用
    private init() {
        setupLogFile()
    }
    
    // 系統日誌器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app.TextCorrection", category: "ErrorReporting")
    
    // 日誌文件URL
    private var logFileURL: URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let logDirectory = documentsDirectory.appendingPathComponent("Logs", isDirectory: true)
        
        // 確保日誌目錄存在
        if !fileManager.fileExists(atPath: logDirectory.path) {
            do {
                try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            } catch {
                print("無法創建日誌目錄: \(error)")
                return nil
            }
        }
        
        // 使用當前日期作為日誌文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = dateFormatter.string(from: Date())
        
        return logDirectory.appendingPathComponent("app_log_\(currentDate).log")
    }
    
    /// 設置日誌文件
    private func setupLogFile() {
        // 確保日誌目錄和文件已準備好
        if let _ = logFileURL {
            log("日誌系統初始化完成", level: .info)
        } else {
            // 如果無法設置文件，至少在控制台輸出警告
            print("警告: 無法初始化日誌文件")
        }
    }
    
    /// 記錄消息到日誌
    /// - Parameters:
    ///   - message: 日誌消息
    ///   - level: 日誌等級
    ///   - file: 源文件
    ///   - function: 函數名
    ///   - line: 行號
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(level.rawValue)] [\(fileName):\(line) \(function)] \(message)"
        
        // 輸出到控制台
        print(logMessage)
        
        // 根據日誌等級使用系統日誌記錄
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .warning:
            logger.warning("\(logMessage)")
        case .error, .critical:
            logger.error("\(logMessage)")
        }
        
        // 寫入到日誌文件
        appendToLogFile(logMessage)
    }
    
    /// 將消息添加到日誌文件
    /// - Parameter message: 要添加的消息
    private func appendToLogFile(_ message: String) {
        guard let fileURL = logFileURL else { return }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)\n"
        
        do {
            // 如果文件存在，附加到現有文件，否則創建新文件
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try logEntry.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("寫入日誌文件時出錯: \(error)")
        }
    }
    
    /// 記錄非致命錯誤
    /// - Parameters:
    ///   - error: 錯誤對象
    ///   - additionalInfo: 附加信息
    ///   - file: 源文件
    ///   - function: 函數名
    ///   - line: 行號
    func recordNonFatalError(_ error: Error, additionalInfo: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var errorInfo = "非致命錯誤: \(error.localizedDescription)"
        
        if let additionalInfo = additionalInfo, !additionalInfo.isEmpty {
            errorInfo += " 附加信息: \(additionalInfo)"
        }
        
        log(errorInfo, level: .error, file: file, function: function, line: line)
        
        // 在這裡可以添加Firebase Crashlytics集成代碼
        // 如: Crashlytics.crashlytics().record(error: error)
    }
    
    /// 獲取所有日誌文件路徑
    /// - Returns: 日誌文件URL數組
    func getLogFiles() -> [URL] {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let logDirectory = documentsDirectory.appendingPathComponent("Logs", isDirectory: true)
        
        guard fileManager.fileExists(atPath: logDirectory.path) else {
            return []
        }
        
        do {
            return try fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }
        } catch {
            log("獲取日誌文件列表失敗: \(error)", level: .error)
            return []
        }
    }
    
    /// 獲取特定日誌文件的內容
    /// - Parameter fileURL: 日誌文件URL
    /// - Returns: 日誌文件內容
    func getLogFileContent(fileURL: URL) -> String? {
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            log("讀取日誌文件失敗: \(error)", level: .error)
            return nil
        }
    }
    
    /// 獲取最近的日誌內容
    /// - Parameter maxLines: 最大行數
    /// - Returns: 最近的日誌內容
    func getRecentLogs(maxLines: Int = 100) -> String {
        guard let fileURL = logFileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return "沒有可用的日誌"
        }
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            
            // 獲取後面的行
            let startIndex = max(0, lines.count - maxLines)
            let recentLines = Array(lines[startIndex..<lines.count])
            
            return recentLines.joined(separator: "\n")
        } catch {
            return "讀取日誌失敗: \(error)"
        }
    }
    
    /// 創建用戶錯誤報告
    /// - Parameters:
    ///   - description: 用戶描述的問題
    ///   - includeLogs: 是否包含日誌
    ///   - screenshotData: 可選的截圖數據
    /// - Returns: 報告數據
    func createUserErrorReport(description: String, includeLogs: Bool = true, screenshotData: Data? = nil) -> Data? {
        var reportDict: [String: Any] = [
            "timestamp": DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .full),
            "description": description,
            "systemInfo": collectSystemInfo()
        ]
        
        if includeLogs {
            reportDict["recentLogs"] = getRecentLogs(maxLines: 200)
        }
        
        if let screenshotData = screenshotData {
            reportDict["hasScreenshot"] = true
            // 實際實現時可能需要將截圖上傳到服務器或包含在報告中
        }
        
        do {
            return try JSONSerialization.data(withJSONObject: reportDict, options: .prettyPrinted)
        } catch {
            log("創建錯誤報告失敗: \(error)", level: .error)
            return nil
        }
    }
    
    /// 收集系統信息
    /// - Returns: 系統信息字典
    private func collectSystemInfo() -> [String: String] {
        // 收集系統信息
        var systemInfo: [String: String] = [:]
        
        // OS版本
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        systemInfo["osVersion"] = osVersion
        
        // 應用版本
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            systemInfo["appVersion"] = "\(appVersion) (\(buildNumber))"
        }
        
        // 設備型號 (macOS)
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        systemInfo["deviceModel"] = String(cString: model)
        
        // 記憶體用量
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        systemInfo["totalMemory"] = "\(physicalMemory / 1024 / 1024) MB"
        
        // CPU使用率 (簡易計算)
        let taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        var flavor = task_flavor_t(MACH_TASK_BASIC_INFO)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &flavor) {
            task_info(mach_task_self_, task_flavor_t($0.pointee), UnsafeMutableRawPointer(&count).assumingMemoryBound(to: Int32.self), &count)
        }
        
        if kerr == KERN_SUCCESS {
            systemInfo["memoryUsage"] = "\(taskInfo.resident_size / 1024 / 1024) MB"
        }
        
        return systemInfo
    }
    
    /// 顯示錯誤報告界面
    /// - Parameters:
    ///   - error: 錯誤信息
    ///   - onSubmit: 提交報告回調
    func showErrorReportUI(error: Error?, onSubmit: @escaping (Data?) -> Void) {
        // 實際實現時，這裡會創建並顯示一個錯誤報告視圖
        // 以下為示例代碼，實際使用時需要調整
        let errorDescription = error?.localizedDescription ?? "應用遇到了問題"
        log("顯示錯誤報告界面: \(errorDescription)", level: .info)
        
        DispatchQueue.main.async {
            // 在這裡可以實現彈出錯誤報告視圖
            // 例如：
            // let errorView = ErrorReportView(error: errorDescription, onSubmit: { description in
            //     let reportData = self.createUserErrorReport(description: description)
            //     onSubmit(reportData)
            // })
            // 顯示視圖...
        }
    }
    
    /// 提交錯誤報告到服務器
    /// - Parameters:
    ///   - reportData: 報告數據
    ///   - completion: 完成回調
    func submitErrorReport(reportData: Data, completion: @escaping (Bool, String?) -> Void) {
        // 實際實現時，這裡會將報告發送到服務器
        // 以下為示例代碼
        log("準備提交錯誤報告", level: .info)
        
        // 假設的API端點
        guard let url = URL(string: "https://your-api-endpoint.com/error-reports") else {
            completion(false, "無效的報告URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = reportData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.log("提交錯誤報告失敗: \(error)", level: .error)
                completion(false, "網絡錯誤: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, "無效的伺服器響應")
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                self.log("錯誤報告提交成功", level: .info)
                completion(true, nil)
            } else {
                let message = "伺服器錯誤: \(httpResponse.statusCode)"
                self.log(message, level: .error)
                completion(false, message)
            }
        }
        
        // 實際應用中取消註釋下面的代碼
        // task.resume()
        
        // 由於這是示例，我們模擬成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.log("模擬錯誤報告提交成功", level: .info)
            completion(true, nil)
        }
    }
}

// MARK: - 錯誤報告視圖示例
struct ErrorReportView: View {
    let error: String
    let onSubmit: (String) -> Void
    
    @State private var userDescription: String = ""
    @State private var includeLogs: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("發生錯誤")
                .font(.title)
                .fontWeight(.bold)
            
            Text("發生了以下錯誤:")
                .font(.subheadline)
            
            Text(error)
                .padding()
                .background(Color(.sRGB, red: 0.95, green: 0.95, blue: 0.95, opacity: 1))
                .cornerRadius(8)
            
            Text("請提供更多關於您在做什麼的信息:")
                .font(.subheadline)
            
            TextEditor(text: $userDescription)
                .frame(height: 100)
                .border(Color.gray.opacity(0.2), width: 1)
            
            Toggle("包含應用日誌", isOn: $includeLogs)
            
            HStack {
                Button("取消") {
                    // 關閉視圖邏輯
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("提交報告") {
                    onSubmit(userDescription)
                    // 關閉視圖邏輯
                }
                .buttonStyle(.borderedProminent)
                .disabled(userDescription.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }
}

// MARK: - SwiftUI 預覽
struct ErrorReportView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorReportView(error: "示例錯誤信息", onSubmit: { _ in })
    }
} 