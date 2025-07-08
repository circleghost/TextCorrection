import Foundation

enum TextCorrectionError: Error, Sendable {
    case apiKeyNotSet
    case invalidResponse
    case apiError(statusCode: Int)
    case timeout
    case encodingError
}