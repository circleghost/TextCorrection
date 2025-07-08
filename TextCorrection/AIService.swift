import Foundation
import os.log
import Network

// MARK: - AI 服務錯誤類型
enum AIServiceError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case clientError(String)
    case modelUnavailable
    case unexpectedError(String)
    case timeout
    case networkUnavailable
    case unsupportedModel
    case apiKeyRequired
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API金鑰無效或已過期，請檢查您的設定"
        case .networkError(let error):
            return "網路連接錯誤：\(error.localizedDescription)"
        case .invalidResponse:
            return "從伺服器收到無效回應，請稍後再試"
        case .serverError(let message):
            return "伺服器錯誤：\(message)"
        case .clientError(let message):
            return "請求錯誤：\(message)"
        case .modelUnavailable:
            return "所請求的AI模型目前不可用，請稍後再試"
        case .unexpectedError(let message):
            return "發生意外錯誤：\(message)"
        case .timeout:
            return "請求超時，請檢查您的網路連接並稍後再試"
        case .networkUnavailable:
            return "無法連接到網路，請檢查您的網路設定"
        case .unsupportedModel:
            return "不支援的AI模型"
        case .apiKeyRequired:
            return "需要設定API金鑰才能使用此模型"
        }
    }
}

// MARK: - 統一的 AI 服務
@MainActor
class AIService: ObservableObject, AIServiceProtocol {
    static let shared = AIService()
    
    private let logger = Logger(subsystem: "com.text.correction", category: "AIService")
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.text.correction.NetworkMonitor")
    private var isNetworkAvailable = true
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - 公共方法
    
    /// 文字校正
    func correctText(_ text: String, model: AIModel) async throws -> String {
        logger.debug("開始文字校正，模型: \(model.displayName)")
        
        // 檢查網路連接
        guard isNetworkAvailable else {
            throw AIServiceError.networkUnavailable
        }
        
        // 檢查 API Key
        let apiKey = AppSettings.shared.getAPIKeyForSelectedModel()
        guard !apiKey.isEmpty else {
            throw AIServiceError.apiKeyRequired
        }
        
        switch model.provider {
        case .openai:
            return try await correctTextWithOpenAI(text, model: model, apiKey: apiKey)
        case .gemini:
            return try await correctTextWithGemini(text, model: model, apiKey: apiKey)
        }
    }
    
    /// 驗證 API Key
    func validateAPIKey(_ apiKey: String, for provider: AIProvider) async throws {
        logger.debug("驗證 API Key，提供商: \(provider.displayName)")
        
        guard isNetworkAvailable else {
            throw AIServiceError.networkUnavailable
        }
        
        guard !apiKey.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }
        
        switch provider {
        case .openai:
            try await validateOpenAIKey(apiKey)
        case .gemini:
            try await validateGeminiKey(apiKey)
        }
    }
    
    // MARK: - OpenAI 實現
    
    private func correctTextWithOpenAI(_ text: String, model: AIModel, apiKey: String) async throws -> String {
        let url = URL(string: model.apiEndpoint)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        let openAIRequest = OpenAIRequest(
            model: model.rawValue,
            messages: [
                OpenAIMessage(role: "system", content: "你是一個專業的中文文字校正助手。請仔細檢查用戶提供的文字，修正其中的錯字、語法錯誤和標點符號問題。只返回修正後的文字內容，不要添加任何解釋或說明。"),
                OpenAIMessage(role: "user", content: text)
            ],
            temperature: 0.1,
            maxTokens: 1024,
            stream: false
        )
        
        request.httpBody = try JSONEncoder().encode(openAIRequest)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                try handleHTTPResponse(httpResponse, data: data)
            }
            
            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let aiResponse = AIResponse.from(openAIResponse: openAIResponse, model: model) else {
                throw AIServiceError.invalidResponse
            }
            
            logger.debug("OpenAI 文字校正完成")
            return aiResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            logger.error("OpenAI 請求失敗: \(error.localizedDescription)")
            throw AIServiceError.networkError(error)
        }
    }
    
    private func validateOpenAIKey(_ apiKey: String) async throws {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        let testRequest = OpenAIRequest(
            model: "gpt-4.1",
            messages: [OpenAIMessage(role: "user", content: "Hi")],
            temperature: 0.1,
            maxTokens: 1,
            stream: false
        )
        
        request.httpBody = try JSONEncoder().encode(testRequest)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                try handleHTTPResponse(httpResponse, data: data)
            }
            
            logger.debug("OpenAI API Key 驗證成功")
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            logger.error("OpenAI API Key 驗證失敗: \(error.localizedDescription)")
            throw AIServiceError.networkError(error)
        }
    }
    
    // MARK: - Gemini 實現
    
    private func correctTextWithGemini(_ text: String, model: AIModel, apiKey: String) async throws -> String {
        let url = URL(string: model.apiEndpoint)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30
        
        let prompt = "你是一個專業的中文文字校正助手。請仔細檢查以下文字，修正其中的錯字、語法錯誤和標點符號問題。只返回修正後的文字內容，不要添加任何解釋或說明。\n\n文字內容：\(text)"
        
        let geminiRequest = GeminiRequest(
            contents: [
                GeminiRequest.GeminiContent(
                    parts: [GeminiRequest.GeminiPart(text: prompt)]
                )
            ]
        )
        
        request.httpBody = try JSONEncoder().encode(geminiRequest)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                try handleHTTPResponse(httpResponse, data: data)
            }
            
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            guard let aiResponse = AIResponse.from(geminiResponse: geminiResponse, model: model) else {
                throw AIServiceError.invalidResponse
            }
            
            logger.debug("Gemini 文字校正完成")
            return aiResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            logger.error("Gemini 請求失敗: \(error.localizedDescription)")
            throw AIServiceError.networkError(error)
        }
    }
    
    private func validateGeminiKey(_ apiKey: String) async throws {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15
        
        let testRequest = GeminiRequest(
            contents: [
                GeminiRequest.GeminiContent(
                    parts: [GeminiRequest.GeminiPart(text: "Hi")]
                )
            ]
        )
        
        request.httpBody = try JSONEncoder().encode(testRequest)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                try handleHTTPResponse(httpResponse, data: data)
            }
            
            logger.debug("Gemini API Key 驗證成功")
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            logger.error("Gemini API Key 驗證失敗: \(error.localizedDescription)")
            throw AIServiceError.networkError(error)
        }
    }
    
    // MARK: - 共用方法
    
    private func handleHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw AIServiceError.invalidAPIKey
        case 400...499:
            if let errorData = try? JSONDecoder().decode([String: Any].self, from: data),
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIServiceError.clientError(message)
            }
            throw AIServiceError.clientError("客戶端錯誤 (HTTP \(response.statusCode))")
        case 500...599:
            if let errorData = try? JSONDecoder().decode([String: Any].self, from: data),
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIServiceError.serverError(message)
            }
            throw AIServiceError.serverError("伺服器錯誤 (HTTP \(response.statusCode))")
        default:
            throw AIServiceError.unexpectedError("未知的HTTP狀態碼: \(response.statusCode)")
        }
    }
}

// MARK: - JSONDecoder 擴展
extension JSONDecoder {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        do {
            return try self.decode(type, from: data)
        } catch {
            print("JSON 解碼錯誤: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("原始 JSON: \(jsonString)")
            }
            throw error
        }
    }
}