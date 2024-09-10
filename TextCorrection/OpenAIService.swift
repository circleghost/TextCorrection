import Foundation

class OpenAIService {
    private let apiKey: String
    private let systemPrompt: String
    
    init(apiKey: String, systemPrompt: String) {
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
    }
    
    func streamOpenAiApi(text: String, onUpdate: @escaping (String) -> Void) async throws {
        print("準備 API 請求...")
        
        let request = OpenAIRequest(
            model: "gpt-4o-mini",
            messages: [
                OpenAIRequest.Message(role: "system", content: systemPrompt),
                OpenAIRequest.Message(role: "user", content: "請將以下文字複寫，只需改錯字及語句不通順的地方。\n\n<text>\n\(text)\n</text>")
            ],
            temperature: 0.7,
            maxTokens: 1000,
            stream: true
        )

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            print("編碼請求時發生錯誤：\(error)")
            throw TextCorrectionError.encodingError
        }

        print("發送 API 請求...")
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TextCorrectionError.invalidResponse
        }
        
        print("收到 API 響應，狀態碼：\(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let data = try? Data(contentsOf: urlRequest.url!),
               let errorString = String(data: data, encoding: .utf8) {
                print("API 錯誤響應：\(errorString)")
            }
            throw TextCorrectionError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("開始解析串流響應...")
        var fullContent = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: String],
                   let content = delta["content"] {
                    fullContent += content
                    onUpdate(content)
                }
            }
        }
        
        // 在這裡添加一個最終的更新，確保使用完整的內容
        onUpdate("\n")  // 添加一個換行符來觸發最後一次更新
        
        print("成功獲取重寫後的文字，總長度：\(fullContent.count)")
        print("API 完整回應：\n\(fullContent)")
    }
}