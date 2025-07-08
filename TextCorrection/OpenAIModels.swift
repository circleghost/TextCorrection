import Foundation

// MARK: - AI 模型配置
enum AIProvider: String, CaseIterable {
    case openai = "OpenAI"
    case gemini = "Gemini"
    
    var displayName: String {
        return rawValue
    }
}

enum AIModel: String, CaseIterable {
    // OpenAI GPT-4.1 系列
    case gpt41 = "gpt-4.1"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt41Nano = "gpt-4.1-nano"
    
    // Gemini 2.0 系列
    case gemini20Flash = "gemini-2.0-flash"
    case gemini25Flash = "gemini-2.5-flash"
    
    var displayName: String {
        switch self {
        case .gpt41:
            return "GPT-4.1"
        case .gpt41Mini:
            return "GPT-4.1 Mini"
        case .gpt41Nano:
            return "GPT-4.1 Nano"
        case .gemini20Flash:
            return "Gemini 2.0 Flash"
        case .gemini25Flash:
            return "Gemini 2.5 Flash"
        }
    }
    
    var provider: AIProvider {
        switch self {
        case .gpt41, .gpt41Mini, .gpt41Nano:
            return .openai
        case .gemini20Flash, .gemini25Flash:
            return .gemini
        }
    }
    
    var apiEndpoint: String {
        switch self {
        case .gpt41, .gpt41Mini, .gpt41Nano:
            return "https://api.openai.com/v1/chat/completions"
        case .gemini20Flash:
            return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
        case .gemini25Flash:
            return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        }
    }
    
    var isOpenAI: Bool {
        return provider == .openai
    }
    
    var isGemini: Bool {
        return provider == .gemini
    }
    
    static var openAIModels: [AIModel] {
        return [.gpt41, .gpt41Mini, .gpt41Nano]
    }
    
    static var geminiModels: [AIModel] {
        return [.gemini20Flash, .gemini25Flash]
    }
}

// MARK: - OpenAI 請求模型
struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Gemini 請求模型
struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    
    struct GeminiContent: Encodable {
        let parts: [GeminiPart]
    }
    
    struct GeminiPart: Encodable {
        let text: String
    }
}

// MARK: - OpenAI 響應模型
struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// MARK: - Gemini 響應模型
struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

struct GeminiCandidate: Codable {
    let content: GeminiContent
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String
}

// MARK: - 通用響應模型
struct AIResponse {
    let content: String
    let model: AIModel
    let provider: AIProvider
    
    static func from(openAIResponse: OpenAIResponse, model: AIModel) -> AIResponse? {
        guard let firstChoice = openAIResponse.choices.first else { return nil }
        return AIResponse(
            content: firstChoice.message.content,
            model: model,
            provider: .openai
        )
    }
    
    static func from(geminiResponse: GeminiResponse, model: AIModel) -> AIResponse? {
        guard let firstCandidate = geminiResponse.candidates.first,
              let firstPart = firstCandidate.content.parts.first else { return nil }
        return AIResponse(
            content: firstPart.text,
            model: model,
            provider: .gemini
        )
    }
}

// MARK: - AI 服務協議
protocol AIServiceProtocol {
    func correctText(_ text: String, model: AIModel) async throws -> String
    func validateAPIKey(_ apiKey: String, for provider: AIProvider) async throws
}