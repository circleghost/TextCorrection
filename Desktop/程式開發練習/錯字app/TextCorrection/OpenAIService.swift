import Foundation
import os.log

/// OpenAI服務：負責處理OpenAI API的調用
class OpenAIService {
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "OpenAIService")
    private let openAIEndpoint = "https://api.openai.com/v1/chat/completions"
    
    /// 驗證API金鑰
    /// - Parameters:
    ///   - apiKey: OpenAI API金鑰
    ///   - completion: 完成後的回調，包含金鑰是否有效
    func validateAPIKey(_ apiKey: String, completion: @escaping (Bool) -> Void) {
        guard !apiKey.isEmpty else {
            logger.warning("API金鑰為空，無法驗證")
            completion(false)
            return
        }
        
        var request = URLRequest(url: URL(string: openAIEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 發送最小請求以驗證金鑰
        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "Hello"],
                ["role": "user", "content": "Test"]
            ],
            "max_tokens": 5
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            logger.error("JSON序列化失敗: \(error.localizedDescription)")
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("API請求錯誤: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("無效的HTTP響應")
                completion(false)
                return
            }
            
            // 檢查HTTP狀態碼
            let isValid = httpResponse.statusCode == 200
            self.logger.debug("API金鑰驗證結果: \(isValid), 狀態碼: \(httpResponse.statusCode)")
            completion(isValid)
        }.resume()
    }
    
    /// 使用OpenAI處理文本
    /// - Parameters:
    ///   - text: 要處理的原始文本
    ///   - systemPrompt: 系統提示詞
    ///   - apiKey: OpenAI API金鑰
    ///   - completion: 完成後的回調，包含處理結果
    func processTextWithPrompt(text: String, systemPrompt: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !text.isEmpty else {
            completion(.failure(OpenAIError.emptyText))
            return
        }
        
        guard !apiKey.isEmpty else {
            completion(.failure(OpenAIError.invalidAPIKey))
            return
        }
        
        var request = URLRequest(url: URL(string: openAIEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 構建請求體
        let body: [String: Any] = [
            "model": "gpt-4-0125-preview",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 4000
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            self.logger.error("JSON序列化失敗: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        let startTime = Date()
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // 計算API響應時間
            let responseTime = Date().timeIntervalSince(startTime)
            self.logger.debug("OpenAI API響應時間: \(responseTime)秒")
            
            if let error = error {
                self.logger.error("API請求錯誤: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("無效的HTTP響應")
                completion(.failure(OpenAIError.invalidResponse))
                return
            }
            
            if httpResponse.statusCode != 200 {
                self.logger.error("API錯誤: HTTP狀態碼 \(httpResponse.statusCode)")
                
                // 嘗試從錯誤響應中提取更詳細的錯誤信息
                if let data = data, let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDetail = errorJson["error"] as? [String: Any],
                   let errorMessage = errorDetail["message"] as? String {
                    completion(.failure(OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)))
                } else {
                    completion(.failure(OpenAIError.apiError(statusCode: httpResponse.statusCode, message: "未知錯誤")))
                }
                return
            }
            
            guard let data = data else {
                self.logger.error("無數據返回")
                completion(.failure(OpenAIError.noData))
                return
            }
            
            do {
                // 解析API響應
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    // 提取反引號之間的內容
                    let correctedText = self.extractTextBetweenTripleBackticks(content) ?? content
                    
                    self.logger.info("文本處理成功，校正後字符數: \(correctedText.count)")
                    completion(.success(correctedText))
                } else {
                    self.logger.error("無法解析API響應")
                    completion(.failure(OpenAIError.parsingError))
                }
            } catch {
                self.logger.error("JSON解析錯誤: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// 從文本中提取三個反引號之間的內容
    /// - Parameter text: 包含反引號部分的文本
    /// - Returns: 提取的文本，如果沒有找到返回nil
    private func extractTextBetweenTripleBackticks(_ text: String) -> String? {
        let pattern = "```([\\s\\S]*?)```"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            if let match = matches.first {
                // 獲取第一個捕獲組（括號內的內容）
                let range = match.range(at: 1)
                return nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            logger.error("正則表達式錯誤: \(error.localizedDescription)")
        }
        
        return nil
    }
}

/// OpenAI相關錯誤
enum OpenAIError: Error {
    case emptyText
    case invalidAPIKey
    case invalidResponse
    case noData
    case parsingError
    case apiError(statusCode: Int, message: String)
    
    var localizedDescription: String {
        switch self {
        case .emptyText:
            return "文本為空，無法處理"
        case .invalidAPIKey:
            return "API金鑰無效或為空"
        case .invalidResponse:
            return "收到無效的API響應"
        case .noData:
            return "API沒有返回數據"
        case .parsingError:
            return "無法解析API響應數據"
        case .apiError(let statusCode, let message):
            return "API錯誤 (HTTP \(statusCode)): \(message)"
        }
    }
}