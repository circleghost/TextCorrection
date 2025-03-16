import Cocoa
import os.log
import NaturalLanguage

class TextProcessing: @unchecked Sendable {
    // 添加日誌對象
    private static let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextProcessing")
    
    static func compareTexts(original: String, rewritten: String, customFont: NSFont) -> NSAttributedString {
        // 記錄比較前的文本
        logger.info("開始比較文本 - 原始文本長度: \(original.count)字符, 重寫文本長度: \(rewritten.count)字符")
        logger.debug("原始文本:\n\(original)")
        logger.debug("重寫文本:\n\(rewritten)")
        
        let attributedString = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8  // 增加行間距
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: customFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .kern: 1.5  // 增加字距
        ]
        
        // 檢查是否只是詞序變化，如果是則不標記為差異
        if isJustWordOrderChange(original, rewritten) {
            attributedString.append(NSAttributedString(string: rewritten, attributes: baseAttributes))
            return attributedString
        }
        
        // 預處理文本，以優化比較效果
        let (processedOriginal, processedRewritten) = preprocessTexts(original: original, rewritten: rewritten)
        
        // 取得差異
        let diff = diffStrings(processedOriginal, processedRewritten)
        
        // 合併和優化差異
        let optimizedDiff = optimizeDiff(diff)
        
        // 使用優化後的差異重新生成 attributedString
        for change in optimizedDiff {
            switch change {
            case .equal(let text):
                // 檢查文本是否為換行符
                if text == "\n" {
                    // 使用段落結束來處理換行
                    let newlineString = NSAttributedString(string: "\n", attributes: baseAttributes)
                    attributedString.append(newlineString)
                } else {
                attributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
                }
            case .insert(let text):
                var attributes = baseAttributes
                attributes[.backgroundColor] = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.3)
                attributes[.foregroundColor] = NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
                
                // 檢查文本是否為換行符
                if text == "\n" {
                    // 插入帶有插入樣式的換行符
                    let newlineString = NSAttributedString(string: "\n", attributes: attributes)
                    attributedString.append(newlineString)
                } else {
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
                }
            case .delete(let text):
                var attributes = baseAttributes
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.red
                attributes[.foregroundColor] = NSColor.red.withAlphaComponent(0.8)
                
                // 檢查文本是否為換行符
                if text == "\n" {
                    // 刪除帶有刪除樣式的換行符
                    let newlineString = NSAttributedString(string: "\n", attributes: attributes)
                    attributedString.append(newlineString)
                } else {
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
                }
            }
        }
        
        return attributedString
    }
    
    // 檢查兩個文本是否只是詞序變化而字符完全相同，特別優化針對「早安」→「安早」這類短詞
    private static func isJustWordOrderChange(_ str1: String, _ str2: String) -> Bool {
        // 如果長度不同，肯定不只是詞序變化
        if str1.count != str2.count {
            return false
        }
        
        // 只處理非常短的2字詞，例如「早安」和「安早」
        // 更長的詞或句子（如「任務交給 AI」和「任務交 AI給」）應視為不同
        if str1.count == 2 && isAllChineseCharacters(str1) && isAllChineseCharacters(str2) {
            // 將兩個字符串轉為字符數組並排序
            let chars1 = str1.sorted()
            let chars2 = str2.sorted()
            return chars1 == chars2
        }
        
        // 針對其他情況，默認不視為詞序變化
        return false
    }
    
    // 檢查字符串是否全部為中文字符
    private static func isAllChineseCharacters(_ str: String) -> Bool {
        for char in str {
            if !isChineseCharacter(char) {
                return false
            }
        }
        return true
    }
    
    // 預處理文本，統一標點符號和空格處理，以優化比較效果
    static func preprocessTexts(original: String, rewritten: String) -> (String, String) {
        // 保留原始空格，不再進行空格標準化
        let trimmedOriginal = original.trimmingCharacters(in: .whitespaces)
        let trimmedRewritten = rewritten.trimmingCharacters(in: .whitespaces)
        
        // 只有純2字詞才考慮詞序問題
        if trimmedOriginal.count == 2 && 
           isJustWordOrderChange(trimmedOriginal, trimmedRewritten) {
            return (trimmedOriginal, trimmedRewritten)
        }
        
        return (trimmedOriginal, trimmedRewritten)
    }
    
    // 移除文本中的多餘空白字符，但保留換行
    static func trimExtraWhitespace(_ text: String) -> String {
        // 保留換行符和所有空格
        return text.trimmingCharacters(in: .whitespaces)
    }
    
    // 為比較準備文本，特殊處理換行符
    private static func prepareTextForComparison(_ text: String) -> String {
        // 此方法用於在比較前對文本進行特殊處理，但不改變實際顯示
        return text
    }
    
    enum DiffChange {
        case equal(String)
        case insert(String)
        case delete(String)
    }
    
    // 優化差異合併，提高可讀性
    static func optimizeDiff(_ diff: [DiffChange]) -> [DiffChange] {
        var optimized = [DiffChange]()
        var currentEqual = ""
        var currentInsert = ""
        var currentDelete = ""
        
        // 檢查當前累積的刪除和插入是否只是順序變更
        let checkForOrderChange = {
            if !currentDelete.isEmpty && !currentInsert.isEmpty {
                // 檢查累積的刪除和插入是否只是順序變更
                if isJustWordOrderChange(currentDelete, currentInsert) {
                    // 直接採用新的順序，不標記為錯誤
                    optimized.append(.equal(currentInsert))
                    currentDelete = ""
                    currentInsert = ""
                    return true
                }
            }
            return false
        }
        
        // 優先處理段落級別的差異
        let processPending = {
            // 首先檢查是否只是詞序變化
            if checkForOrderChange() {
                // 如果是詞序變化，已在checkForOrderChange中處理
            } else if !currentDelete.isEmpty && !currentInsert.isEmpty {
                // 使用更高級的差異比較來檢測相似但有修改的短語
                if isSignificantlySimilar(currentDelete, currentInsert) {
                    // 如果文本非常相似，找出確切的差異
                    let detailedDiff = diffStringsDetailed(currentDelete, currentInsert)
                    optimized.append(contentsOf: detailedDiff)
                } else {
                    // 否則展示為刪除後插入
                    optimized.append(.delete(currentDelete))
                    optimized.append(.insert(currentInsert))
                }
                currentDelete = ""
                currentInsert = ""
            } else if !currentDelete.isEmpty {
                optimized.append(.delete(currentDelete))
                currentDelete = ""
            } else if !currentInsert.isEmpty {
                optimized.append(.insert(currentInsert))
                currentInsert = ""
            }
            
            // 最後處理相等部分
            if !currentEqual.isEmpty {
                optimized.append(.equal(currentEqual))
                currentEqual = ""
            }
        }
        
        // 分析差異，根據上下文優化顯示
        for change in diff {
            switch change {
            case .equal(let text):
                // 處理待處理的變更
                processPending()
                // 累積新的相等部分
                currentEqual += text
                
            case .insert(let text):
                // 處理任何待處理的相等部分
                if !currentEqual.isEmpty {
                    optimized.append(.equal(currentEqual))
                    currentEqual = ""
                }
                // 累積插入內容
                currentInsert += text
                
            case .delete(let text):
                // 處理任何待處理的相等部分
                if !currentEqual.isEmpty {
                    optimized.append(.equal(currentEqual))
                    currentEqual = ""
                }
                // 累積刪除內容
                currentDelete += text
            }
        }
        
        // 處理剩餘的待處理內容
        processPending()
        
        // 合併相鄰的相同類型變更
        return mergeAdjacentChanges(optimized)
    }
    
    // 檢查兩個字符串是否非常相似（只有微小的差異）
    private static func isSignificantlySimilar(_ str1: String, _ str2: String) -> Bool {
        // 先檢查是否只是詞序變化
        if isJustWordOrderChange(str1, str2) {
            return true
        }
        
        // 檢查長度差異
        let lengthDiff = abs(str1.count - str2.count)
        if lengthDiff > min(str1.count, str2.count) / 3 {
            return false
        }
        
        // 中文詞序變化檢測 - 針對短語
        if str1.count <= 10 && str2.count <= 10 {
            // 計算兩個字符串中相同字符的數量
            let set1 = Set(str1)
            let set2 = Set(str2)
            let commonChars = set1.intersection(set2)
            
            // 如果超過80%的字符是共同的，可能是詞序變化或小幅修改
            if Double(commonChars.count) / Double(max(set1.count, set2.count)) > 0.8 {
                return true
            }
        }
        
        // 計算編輯距離
        let distance = levenshteinDistance(str1, str2)
        let maxLength = max(str1.count, str2.count)
        let similarityRatio = Double(maxLength - distance) / Double(maxLength)
        
        // 提高相似度閾值，避免誤判
        return similarityRatio > 0.75
    }
    
    // 計算兩個字符串的編輯距離（Levenshtein 距離）
    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aCount = a.count
        let bCount = b.count
        
        if aCount == 0 { return bCount }
        if bCount == 0 { return aCount }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: bCount + 1), count: aCount + 1)
        
        // 初始化第一行和第一列
        for i in 0...aCount {
            matrix[i][0] = i
        }
        for j in 0...bCount {
            matrix[0][j] = j
        }
        
        let aArray = Array(a)
        let bArray = Array(b)
        
        // 填充矩陣
        for i in 1...aCount {
            for j in 1...bCount {
                let cost = aArray[i-1] == bArray[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // 刪除
                    matrix[i][j-1] + 1,      // 插入
                    matrix[i-1][j-1] + cost  // 替換
                )
            }
        }
        
        return matrix[aCount][bCount]
    }
    
    // 更詳細的差異比較，特別用於相似但有修改的短語
    static func diffStringsDetailed(_ old: String, _ new: String) -> [DiffChange] {
        // 使用基本的 diffStrings 獲取初步差異
        let basicDiff = diffStrings(old, new)
        
        // 直接返回基本差異，不做額外處理
        return basicDiff
    }
    
    // 合併相鄰的相同類型變更
    private static func mergeAdjacentChanges(_ changes: [DiffChange]) -> [DiffChange] {
        var result = [DiffChange]()
        
        for change in changes {
            if let lastChange = result.last {
                switch (lastChange, change) {
                case (.equal(let prev), .equal(let curr)):
                    result[result.count - 1] = .equal(prev + curr)
                case (.insert(let prev), .insert(let curr)):
                    result[result.count - 1] = .insert(prev + curr)
                case (.delete(let prev), .delete(let curr)):
                    result[result.count - 1] = .delete(prev + curr)
                default:
                    result.append(change)
                }
            } else {
                result.append(change)
            }
        }
        
        return result
    }
    
    // 使用改進的字元級比較算法，專注於錯字檢測
    static func diffStrings(_ old: String, _ new: String) -> [DiffChange] {
        // 記錄比較前的文本內容
        logger.debug("比較前原始文本:\n\(old)")
        logger.debug("比較前重寫文本:\n\(new)")
        
        // 完全相同的文本直接返回相等
        if old == new {
            return [.equal(old)]
        }
        
        // 短文本特殊處理
        if old.count <= 3 && old.count >= 2 && new.count <= 3 && new.count >= 2 {
            if isJustWordOrderChange(old, new) {
                return [.equal(new)]
            }
        }
        
        // 將文本分割為段落，以換行符為界
        let oldParagraphs = old.components(separatedBy: "\n")
        let newParagraphs = new.components(separatedBy: "\n")
        
        var result = [DiffChange]()
        
        // 比較每個段落
        let maxParagraphCount = max(oldParagraphs.count, newParagraphs.count)
        
        for i in 0..<maxParagraphCount {
            // 獲取當前段落，如果索引超出範圍則使用空字符串
            let oldParagraph = i < oldParagraphs.count ? oldParagraphs[i] : ""
            let newParagraph = i < newParagraphs.count ? newParagraphs[i] : ""
            
            // 如果段落相同，直接添加為相等
            if oldParagraph == newParagraph {
                if !oldParagraph.isEmpty {
                    result.append(.equal(oldParagraph))
                }
            } else {
                // 對不同的段落進行字元級別的比較
                let paragraphDiff = diffStringsByCharacter(oldParagraph, newParagraph)
                result.append(contentsOf: paragraphDiff)
            }
            
            // 如果不是最後一個段落，添加換行符
            if i < maxParagraphCount - 1 {
                result.append(.equal("\n"))
            }
        }
        
        // 記錄比較結果
        logger.debug("段落比較完成，總共比較了 \(maxParagraphCount) 個段落")
        
        return result
    }
    
    // 字元級別的比較算法，專注於錯字檢測
    private static func diffStringsByCharacter(_ old: String, _ new: String) -> [DiffChange] {
        // 完全相同的文本直接返回相等
        if old == new {
            return [.equal(old)]
        }
        
        // 特殊處理2字元的中文短詞
        if old.count == 2 && isAllChineseCharacters(old) && isAllChineseCharacters(new) && 
           isJustWordOrderChange(old, new) {
            return [.equal(new)]
        }
        
        // 進行基本的字元級比較
        let oldChars = Array(old)
        let newChars = Array(new)
        let m = oldChars.count
        let n = newChars.count
        
        // 如果任一字符串為空，直接返回結果
        if m == 0 {
            return [.insert(new)]
        }
        if n == 0 {
            return [.delete(old)]
        }
        
        // 構建 LCS 表
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
        
        // 基於 LCS 構建差異序列
        var diff = [DiffChange]()
        var i = m, j = n
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldChars[i-1] == newChars[j-1] {
                // 當前字符相同
                diff.insert(.equal(String(oldChars[i-1])), at: 0)
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                // 插入發生的情況
                diff.insert(.insert(String(newChars[j-1])), at: 0)
                j -= 1
            } else {
                // 刪除發生的情況
                diff.insert(.delete(String(oldChars[i-1])), at: 0)
                i -= 1
            }
        }
        
        // 後處理差異序列，修復誤判情況
        return postProcessDiff(diff, originalText: old)
    }
    
    // 後處理差異序列，修復誤判情況
    private static func postProcessDiff(_ diff: [DiffChange], originalText: String) -> [DiffChange] {
        // 簡單後處理：合併相鄰的相同類型差異
        var optimizedDiff = [DiffChange]()
        var currentEqual = ""
        var currentInsert = ""
        var currentDelete = ""
        
        // 處理函數，將累積的變更添加到結果中
        let processPending = {
            // 特殊處理：檢查是否有刪除和插入相同字符的情況
            if !currentDelete.isEmpty && !currentInsert.isEmpty {
                // 特殊情況1：完全相同的字符被標記為刪除和插入
                if currentDelete == currentInsert {
                    optimizedDiff.append(.equal(currentDelete))
                    currentDelete = ""
                    currentInsert = ""
                    return
                }
                
                // 特殊情況2：檢查相同字符在相鄰位置出現
                let deleteChars = Array(currentDelete)
                let insertChars = Array(currentInsert)
                
                // 使用集合找出共同字符
                let deleteSet = Set(deleteChars)
                let insertSet = Set(insertChars)
                let commonChars = deleteSet.intersection(insertSet)
                
                // 檢查當刪除字符和插入字符高度相似時（例如只是位置不同）
                if !commonChars.isEmpty && 
                   Double(commonChars.count) / Double(max(deleteSet.count, insertSet.count)) > 0.7 {
                    // 構建修正後的顯示文本
                    var result = ""
                    var usedDeleteIndices = Set<Int>()
                    var usedInsertIndices = Set<Int>()
                    
                    // 遍歷兩個字符數組，尋找相同字符，優先保留它們
                    for (dIndex, dChar) in deleteChars.enumerated() {
                        for (iIndex, iChar) in insertChars.enumerated() {
                            if dChar == iChar && !usedDeleteIndices.contains(dIndex) && !usedInsertIndices.contains(iIndex) {
                                result += String(dChar)
                                usedDeleteIndices.insert(dIndex)
                                usedInsertIndices.insert(iIndex)
                                break
                            }
                        }
                    }
                    
                    // 添加剩餘的刪除和插入字符
                    for (index, char) in deleteChars.enumerated() {
                        if !usedDeleteIndices.contains(index) {
                            optimizedDiff.append(.delete(String(char)))
                        }
                    }
                    
                    if !result.isEmpty {
                        optimizedDiff.append(.equal(result))
                    }
                    
                    for (index, char) in insertChars.enumerated() {
                        if !usedInsertIndices.contains(index) {
                            optimizedDiff.append(.insert(String(char)))
                        }
                    }
                    
                    currentDelete = ""
                    currentInsert = ""
                    return
                }
            }
            
            // 處理常規情況
            if !currentEqual.isEmpty {
                optimizedDiff.append(.equal(currentEqual))
                currentEqual = ""
            }
            if !currentDelete.isEmpty {
                optimizedDiff.append(.delete(currentDelete))
                currentDelete = ""
            }
            if !currentInsert.isEmpty {
                optimizedDiff.append(.insert(currentInsert))
                currentInsert = ""
            }
        }
        
        // 合併相鄰的變更
        for change in diff {
            switch change {
            case .equal(let text):
                if !currentInsert.isEmpty || !currentDelete.isEmpty {
                    processPending()
                }
                currentEqual += text
            case .insert(let text):
                if !currentEqual.isEmpty {
                    optimizedDiff.append(.equal(currentEqual))
                    currentEqual = ""
                }
                currentInsert += text
            case .delete(let text):
                if !currentEqual.isEmpty {
                    optimizedDiff.append(.equal(currentEqual))
                    currentEqual = ""
                }
                currentDelete += text
            }
        }
        
        // 處理剩餘的變更
        processPending()
        
        // 檢查最終結果中是否包含任何實際變更
        var hasChanges = false
        for change in optimizedDiff {
            switch change {
            case .insert(_), .delete(_):
                hasChanges = true
                break
            case .equal(_):
                continue
            }
            if hasChanges {
                break
            }
        }
        
        // 如果沒有實際變更但文本可能看起來相同，直接返回相等
        if !hasChanges {
            return [.equal(originalText)]
        }
        
        return optimizedDiff
    }
    
    // 輔助方法：檢查是否為中文字符
    private static func isChineseCharacter(_ char: Character) -> Bool {
        let scalars = char.unicodeScalars
        return scalars.contains { scalar in
            (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||   // CJK Unified Ideographs
            (scalar.value >= 0x3400 && scalar.value <= 0x4DBF) ||   // CJK Unified Ideographs Extension A
            (scalar.value >= 0x20000 && scalar.value <= 0x2A6DF)    // CJK Unified Ideographs Extension B
        }
    }
    
    // 檢查是否為英文字符
    private static func isEnglishChar(_ char: Character) -> Bool {
        return char.isASCII && char.isLetter
    }
    
    // 檢查是否為數字
    private static func isDigit(_ char: Character) -> Bool {
        return char.isASCII && char.isNumber
    }
    
    // 檢查是否為中文標點符號
    private static func isChinesePunctuation(_ char: Character) -> Bool {
        let chinesePunctuations = "，。、；：？！\"'（）【】《》"
        return chinesePunctuations.contains(char)
    }
    
    // 檢查是否為西文標點符號
    private static func isWesternPunctuation(_ char: Character) -> Bool {
        let westernPunctuations = ",.;:?!\"'()[]{}<>"
        return westernPunctuations.contains(char)
    }
    
    // 計算原始文本和重寫文本之間的變更詞數
    static func calculateChangedWords(original: String, rewritten: String) -> Int {
        guard !original.isEmpty, !rewritten.isEmpty else {
            return 0
        }
        
        // 將文本分詞
        let originalWords = tokenizeText(original)
        let rewrittenWords = tokenizeText(rewritten)
        
        // 使用Levenshtein距離算法計算編輯距離
        let distance = levenshteinDistance(originalWords, rewrittenWords)
        
        logger.debug("原文詞數: \(originalWords.count), 修改後詞數: \(rewrittenWords.count), 編輯距離: \(distance)")
        
        return distance
    }
    
    /// 對文本進行分詞
    /// - Parameter text: 要分詞的文本
    /// - Returns: 分詞結果數組
    private static func tokenizeText(_ text: String) -> [String] {
        var words: [String] = []
        
        // 創建中文分詞器
        let tokenizer = NLTokenizer(using: .word)
        tokenizer.string = text
        
        // 進行分詞
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            // 過濾空白和標點符號
            if !word.trimmingCharacters(in: .whitespacesAndPunctuation).isEmpty {
                words.append(word)
            }
            return true
        }
        
        return words
    }
    
    /// 計算兩個數組之間的Levenshtein距離（編輯距離）
    /// - Parameters:
    ///   - a: 第一個數組
    ///   - b: 第二個數組
    /// - Returns: 編輯距離
    private static func levenshteinDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        // 創建一個(a.count+1) x (b.count+1)的矩陣
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        
        // 初始化第一行和第一列
        for i in 0...a.count {
            matrix[i][0] = i
        }
        
        for j in 0...b.count {
            matrix[0][j] = j
        }
        
        // 填充矩陣
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,     // 刪除
                    matrix[i][j-1] + 1,     // 插入
                    matrix[i-1][j-1] + cost // 替換或保持
                )
            }
        }
        
        // 返回右下角的值，即編輯距離
        return matrix[a.count][b.count]
    }
    
    /// 計算文本中的字符數（不包括空白字符）
    /// - Parameter text: 要計算的文本
    /// - Returns: 字符數
    static func countNonWhitespaceCharacters(_ text: String) -> Int {
        return text.filter { !$0.isWhitespace }.count
    }
    
    /// 高亮顯示原文和修改後文本的差異
    /// - Parameters:
    ///   - original: 原始文本
    ///   - corrected: 校正後的文本
    /// - Returns: 用HTML標記差異的字符串
    static func highlightDifferences(original: String, corrected: String) -> String {
        // 這裡可以使用diff算法來高亮顯示差異
        // 簡單起見，這裡返回一個未實現的提示
        return "差異高亮功能尚未實現"
    }
}

// 擴展 String 以支持更多檢查方法
extension String {
    func containsOnlyPunctuation() -> Bool {
        let punctuationCharSet = CharacterSet.punctuationCharacters
        return !isEmpty && unicodeScalars.allSatisfy { punctuationCharSet.contains($0) }
    }
    
    func isAllWhitespace() -> Bool {
        return !isEmpty && allSatisfy { $0.isWhitespace }
    }
}

// 擴展 DiffChange 以支持更多檢查方法
extension TextProcessing.DiffChange {
    func containsChineseCharacters() -> Bool {
        switch self {
        case .equal(let text), .insert(let text), .delete(let text):
            return text.contains { char in
                let scalars = char.unicodeScalars
                return scalars.contains { scalar in
                    (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||
                    (scalar.value >= 0x3400 && scalar.value <= 0x4DBF) ||
                    (scalar.value >= 0x20000 && scalar.value <= 0x2A6DF)
                }
            }
        }
    }
}
