import Foundation
import os.log

enum TextCorrectionError: Error, Sendable, LocalizedError {
    case apiKeyNotSet
    case invalidResponse
    case apiError(statusCode: Int)
    case timeout
    case encodingError
    case networkError(String)
    case processingError(String)
    case invalidInput(String)
    case textTooLong(Int)
    case serviceUnavailable
    case rateLimitExceeded
    case unexpectedError(String)
    case permissionDenied
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotSet:
            return "缺少 API 金鑰"
        case .invalidResponse:
            return "無效的 API 回應"
        case .apiError(let statusCode):
            return "API 錯誤 (狀態碼: \(statusCode))"
        case .timeout:
            return "請求逾時"
        case .encodingError:
            return "編碼錯誤"
        case .networkError(let message):
            return "網路錯誤: \(message)"
        case .processingError(let message):
            return "處理錯誤: \(message)"
        case .invalidInput(let message):
            return "無效輸入: \(message)"
        case .textTooLong(let length):
            return "文本太長（\(length) 字符）"
        case .serviceUnavailable:
            return "服務不可用"
        case .rateLimitExceeded:
            return "請求頻率超過限制"
        case .unexpectedError(let message):
            return "未預期的錯誤: \(message)"
        case .permissionDenied:
            return "權限不足"
        case .fileSystemError(let message):
            return "檔案系統錯誤: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .apiKeyNotSet:
            return "請在偏好設定中設定 OpenAI API 金鑰"
        case .invalidResponse:
            return "請稍後再試，或檢查 API 金鑰是否正確"
        case .apiError(let statusCode):
            switch statusCode {
            case 401:
                return "請檢查您的 API 金鑰是否正確"
            case 429:
                return "請稍等片刻後再試"
            case 500...599:
                return "伺服器暫時不可用，請稍後再試"
            default:
                return "請檢查您的請求設定"
            }
        case .timeout:
            return "請檢查您的網路連線或稍後再試"
        case .encodingError:
            return "請檢查輸入文本的格式"
        case .networkError:
            return "請檢查您的網路連線"
        case .processingError:
            return "請稍後再試"
        case .invalidInput:
            return "請檢查輸入的內容"
        case .textTooLong:
            return "請縮短文本長度"
        case .serviceUnavailable:
            return "請稍後再試"
        case .rateLimitExceeded:
            return "請稍等片刻後再試"
        case .unexpectedError:
            return "如果問題持續，請聯繫開發者"
        case .permissionDenied:
            return "請在系統偏好設定中授予必要的權限"
        case .fileSystemError:
            return "請檢查檔案權限或可用空間"
        }
    }
}

// 統一的錯誤處理器
@MainActor
class ErrorHandler {
    static let shared = ErrorHandler()
    private let logger = Logger(subsystem: "com.text.correction", category: "ErrorHandler")
    
    private init() {}
    
    /// 處理並顯示錯誤
    func handle(_ error: Error, context: String = "") {
        let errorMessage: String
        let recoverySuggestion: String?
        
        if let appError = error as? TextCorrectionError {
            errorMessage = appError.errorDescription ?? "未知錯誤"
            recoverySuggestion = appError.recoverySuggestion
        } else {
            errorMessage = error.localizedDescription
            recoverySuggestion = nil
        }
        
        // 記錄錯誤
        let logMessage = context.isEmpty ? errorMessage : "\(context): \(errorMessage)"
        logger.error("\(logMessage)")
        
        // 更新 AppState 以顯示錯誤
        AppState.shared.errorMessage = errorMessage
        
        // 如果有恢復建議，也顯示給用戶
        if let suggestion = recoverySuggestion {
            AppState.shared.addNotification(
                title: "錯誤",
                message: "\(errorMessage)\n\n建議: \(suggestion)",
                type: .error
            )
        }
    }
    
    /// 處理非致命性警告
    func handleWarning(_ message: String, context: String = "") {
        let logMessage = context.isEmpty ? message : "\(context): \(message)"
        logger.warning("\(logMessage)")
        
        AppState.shared.addNotification(
            title: "警告",
            message: message,
            type: .warning
        )
    }
    
    /// 處理資訊性訊息
    func handleInfo(_ message: String, context: String = "") {
        let logMessage = context.isEmpty ? message : "\(context): \(message)"
        logger.info("\(logMessage)")
        
        AppState.shared.addNotification(
            title: "資訊",
            message: message,
            type: .info
        )
    }
}