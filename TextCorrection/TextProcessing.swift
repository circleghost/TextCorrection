import Cocoa

class TextProcessing {
    static func compareTexts(original: String, rewritten: String, customFont: NSFont) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8  // 增加行間距
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: customFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .kern: 1.5  // 增加字距
        ]
        
        let diff = diffStrings(original, rewritten)
        
        for change in diff {
            switch change {
            case .equal(let text):
                attributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .insert(let text):
                var attributes = baseAttributes
                attributes[.backgroundColor] = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.3)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            case .delete(let text):
                var attributes = baseAttributes
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.red
                attributes[.backgroundColor] = NSColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 0.3)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        
        return attributedString
    }
    
    enum DiffChange {
        case equal(String)
        case insert(String)
        case delete(String)
    }
    
    static func diffStrings(_ old: String, _ new: String) -> [DiffChange] {
        let oldChars = Array(old)
        let newChars = Array(new)
        let m = oldChars.count
        let n = newChars.count
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...m {
            for j in 1...n {
                if oldChars[i-1] == newChars[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        var diff = [DiffChange]()
        var i = m, j = n
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldChars[i-1] == newChars[j-1] {
                diff.insert(.equal(String(oldChars[i-1])), at: 0)
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                diff.insert(.insert(String(newChars[j-1])), at: 0)
                j -= 1
            } else {
                diff.insert(.delete(String(oldChars[i-1])), at: 0)
                i -= 1
            }
        }
        
        return diff
    }
}