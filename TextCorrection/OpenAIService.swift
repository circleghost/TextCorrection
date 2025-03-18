import Foundation
import os.log

enum OpenAIError: Error {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case clientError(String)
    case modelUnavailable
    case unexpectedError(String)
    case timeout
}

// 完整的類實現，而不是擴展
class OpenAIService: @unchecked Sendable {
    // 日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "OpenAIService")
    
    // API基本URL
    private let apiURL = "https://api.openai.com/v1/chat/completions"
    
    // 初始化
    init() {
        logger.debug("OpenAIService初始化")
    }
    
    // 驗證API金鑰
    func validateAPIKey(_ apiKey: String) async throws {
        logger.debug("驗證API金鑰")
        
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
    @Sendable
    func streamOpenAiApi(
        text: String, 
        apiKeyProvider: @Sendable @escaping () -> String, 
        systemPrompt: String = "", 
        onNewContent: @escaping (String) -> Void
    ) async throws {
        logger.debug("準備 API 請求...")
        
        guard let url = URL(string: apiURL) else {
            logger.error("無效的API URL")
            throw OpenAIError.unexpectedError("無效的API URL")
        }
        
        // 創建請求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKeyProvider())", forHTTPHeaderField: "Authorization")

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
            throw OpenAIError.unexpectedError("請求序列化錯誤")
        }
        
        logger.debug("發送 API 請求...")
        
        // 執行請求並獲取流式回應
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("無效的HTTP響應")
                throw OpenAIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
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
            // 重新拋出特定的OpenAIError
            logger.error("OpenAI錯誤: \(apiError)")
            throw apiError
        } catch {
            logger.error("未知錯誤: \(error.localizedDescription)")
            throw OpenAIError.unexpectedError(error.localizedDescription)
        }
    }
    
    @Sendable
    func testApiKey(apiKeyProvider: @escaping () -> String) async throws -> Bool {
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
}