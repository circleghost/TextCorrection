import Foundation

enum TextCorrectionError: Error {
    case apiKeyNotSet
    case invalidResponse
    case apiError(statusCode: Int)
    case timeout
    case encodingError
}