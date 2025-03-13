import Foundation

enum TextCorrectionError: Error, @unchecked Sendable {
    case apiKeyNotSet
    case invalidResponse
    case apiError(statusCode: Int)
    case timeout
    case encodingError
}