import Foundation
import os.log
import Network

enum OpenAIError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case clientError(String)
    case modelUnavailable
    case unexpectedError(String)
    case timeout
    case networkUnavailable
    
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
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidAPIKey:
            return "請前往設定頁面重新輸入有效的API金鑰"
        case .networkError:
            return "請檢查您的網路連接是否正常，或稍後再試"
        case .networkUnavailable:
            return "請確認您已連接到網路，並且沒有防火牆或網路限制"
        case .timeout:
            return "若問題持續，可能是網路連接不穩定或伺服器負載過高"
        default:
            return "如果問題持續發生，請聯絡開發者支援"
        }
    }
}

// 使用 Actor 確保線程安全
actor OpenAIService {
    // 日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "OpenAIService")
    
    // API基本URL
    private let apiURL = "https://api.openai.com/v1/chat/completions"
    
    // 網路監控
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.yourcompany.TextCorrection.NetworkMonitor")
    private var isNetworkAvailable = true
    
    // 初始化
    init() {
        logger.debug("OpenAIService初始化")
        setupNetworkMonitoring()
    }
    
    // 設置網路監控
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.isNetworkAvailable = path.status == .satisfied
            self.logger.debug("網路狀態更新: \(self.isNetworkAvailable ? "可用" : "不可用")")
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // 驗證API金鑰
    func validateAPIKey(_ apiKey: String) async throws {
        logger.debug("驗證API金鑰")
        
        // 檢查網路連接
        guard isNetworkAvailable else {
            logger.error("網路不可用，無法驗證API金鑰")
            throw OpenAIError.networkUnavailable
        }
        
        // 創建一個簡單的請求以檢查API金鑰是否有效
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            logger.error("無效的API URL")
            throw OpenAIError.unexpectedError("無效的API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            // 設置超時時間為10秒
            let (_, response) = try await URLSession.shared.data(for: request, delegate: nil)
            
            // 檢查HTTP狀態碼
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("無法獲取HTTP響應")
                throw OpenAIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                logger.debug("API金鑰驗證成功")
                return // 成功
            case 401:
                logger.error("API金鑰無效")
                throw OpenAIError.invalidAPIKey
            case 400...499:
                logger.error("客戶端錯誤: \(httpResponse.statusCode)")
                throw OpenAIError.clientError("HTTP \(httpResponse.statusCode)")
            case 500...599:
                logger.error("服務器錯誤: \(httpResponse.statusCode)")
                throw OpenAIError.serverError("HTTP \(httpResponse.statusCode)")
            default:
                logger.error("未預期的狀態碼: \(httpResponse.statusCode)")
                throw OpenAIError.unexpectedError("未預期的狀態碼: \(httpResponse.statusCode)")
            }
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                logger.error("請求超時")
                throw OpenAIError.timeout
            } else {
                logger.error("網絡錯誤: \(urlError.localizedDescription)")
                throw OpenAIError.networkError(urlError)
            }
        } catch let apiError as OpenAIError {
            // 重新拋出OpenAIError
            throw apiError
        } catch {
            logger.error("未知錯誤: \(error.localizedDescription)")
            throw OpenAIError.unexpectedError(error.localizedDescription)
        }
    }
    
    // 使用流式API處理文本，通過回調提供更新
    func streamOpenAiApi(
        text: String, 
        apiKeyProvider: @Sendable @escaping () -> String, 
        systemPrompt: String = "", 
        onNewContent: @Sendable @escaping (String) -> Void,
        onError: @Sendable @escaping (OpenAIError) -> Void = { _ in }
    ) async throws {
        logger.debug("準備 API 請求...")
        
        // 檢查網路連接
        guard isNetworkAvailable else {
            logger.error("網路不可用，無法進行API請求")
            let error = OpenAIError.networkUnavailable
            onError(error)
            throw error
        }
        
        // 檢查API金鑰
        let apiKey = apiKeyProvider()
        if apiKey.isEmpty {
            logger.error("API金鑰為空")
            let error = OpenAIError.invalidAPIKey
            onError(error)
            throw error
        }
        
        guard let url = URL(string: apiURL) else {
            logger.error("無效的API URL")
            let error = OpenAIError.unexpectedError("無效的API URL")
            onError(error)
            throw error
        }
        
        // 創建請求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 設置請求超時
        request.timeoutInterval = 30

        // 準備請求正文
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "請將以下文字複寫，只需改錯字及語句不通順的地方。\n\n<text>\n\(text)\n</text>"]
            ],
            "temperature": 0.7,
            "max_tokens": 2000,
            "stream": true
        ]
        
        // 序列化請求正文
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("請求序列化錯誤: \(error.localizedDescription)")
            let apiError = OpenAIError.unexpectedError("請求序列化錯誤: \(error.localizedDescription)")
            onError(apiError)
            throw apiError
        }
        
        logger.debug("發送 API 請求...")
        
        // 執行請求並獲取流式回應
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("無效的HTTP響應")
                let error = OpenAIError.invalidResponse
                onError(error)
                throw error
            }
            
            // 檢查是否有錯誤訊息
            if httpResponse.statusCode != 200 {
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                
                // 嘗試獲取錯誤響應內容
                if let errorData = try? await bytes.reduce(into: Data(), { data, byte in
                    data.append(byte)
                }) {
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorMessage = message
                    }
                }
                
                switch httpResponse.statusCode {
                case 401:
                    logger.error("API金鑰無效: \(errorMessage)")
                    let error = OpenAIError.invalidAPIKey
                    onError(error)
                    throw error
                case 429:
                    logger.error("請求頻率限制: \(errorMessage)")
                    let error = OpenAIError.clientError("請求頻率限制: \(errorMessage)")
                    onError(error)
                    throw error
                case 400...499:
                    logger.error("客戶端錯誤: \(errorMessage)")
                    let error = OpenAIError.clientError(errorMessage)
                    onError(error)
                    throw error
                case 500...599:
                    logger.error("服務器錯誤: \(errorMessage)")
                    let error = OpenAIError.serverError(errorMessage)
                    onError(error)
                    throw error
                default:
                    logger.error("未預期的狀態碼: \(httpResponse.statusCode) - \(errorMessage)")
                    let error = OpenAIError.unexpectedError("未預期的狀態碼: \(httpResponse.statusCode) - \(errorMessage)")
                    onError(error)
                    throw error
                }
            }
            
            logger.debug("API請求成功，開始處理回應")
            
            // 解析流式回應
            var fullContent = ""
            for try await line in bytes.lines {
                if line == "data: [DONE]" {
                    break
                }
                
                if line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            
                            fullContent += content
                            onNewContent(content)
                        }
                    } catch {
                        logger.warning("解析流式數據失敗: \(error.localizedDescription)")
                        // 繼續處理後續數據
                    }
                }
            }
            
            logger.debug("流式回應處理完成，總字符數: \(fullContent.count)")
        } catch let urlError as URLError {
            var apiError: OpenAIError
            
            switch urlError.code {
            case .timedOut:
                logger.error("請求超時")
                apiError = OpenAIError.timeout
            case .notConnectedToInternet:
                logger.error("未連接到網路")
                apiError = OpenAIError.networkUnavailable
            case .networkConnectionLost:
                logger.error("網路連接中斷")
                apiError = OpenAIError.networkError(urlError)
            default:
                logger.error("網絡錯誤: \(urlError.localizedDescription)")
                apiError = OpenAIError.networkError(urlError)
            }
            
            onError(apiError)
            throw apiError
        } catch {
            logger.error("未知錯誤: \(error.localizedDescription)")
            let apiError = OpenAIError.unexpectedError(error.localizedDescription)
            onError(apiError)
            throw apiError
        }
    }
    
    func testApiKey(apiKeyProvider: @Sendable @escaping () -> String) async throws -> Bool {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKeyProvider())", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            return httpResponse.statusCode == 200
        }
        
        return false
    }
    
    /// 檢查服務是否可用
    nonisolated func isAvailable() -> Bool {
        // 檢查是否有有效的API密鑰
        if UserDefaults.standard.string(forKey: "openai_api_key")?.isEmpty ?? true {
            return false
        }
        
        // 注意：這裡簡化實現，實際應該通過 async 方法獲取網路狀態
        return true // 簡化實現，避免跨隔離域訪問
    }
}