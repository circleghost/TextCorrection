import Cocoa
import os.log

class TextProcessing: @unchecked Sendable {
    // 添加日誌對象
    private static let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextProcessing")
    
    // 添加粉圓體字體輔助方法
    private static func getPungyuFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        // 嘗試多種可能的粉圓體字體名稱
        let fontNames = ["jf-openhuninn", "JF Open Huninn", "粉圓體", "jf粉圓體", "JF粉圓體"]
        
        for name in fontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        
        // 如果找不到粉圓體，回退到系統字體
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
    
    static func compareTexts(original: String, rewritten: String, customFont: NSFont) -> NSAttributedString {
        // 記錄比較前的文本
        logger.info("開始比較文本 - 原始文本長度: \(original.count)字符, 重寫文本長度: \(rewritten.count)字符")
        logger.debug("原始文本:\n\(original)")
        logger.debug("重寫文本:\n\(rewritten)")
        
        let attributedString = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8  // 增加行間距
        
        // 使用粉圓體字體替代customFont
        let pungyuFont = getPungyuFont(size: 26)
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: pungyuFont,
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
    
    // 優化差異合併函數，提高效能並修正記憶體使用
    static func optimizeDiff(_ diff: [DiffChange]) -> [DiffChange] {
        guard !diff.isEmpty else { return [] }
        
        // 使用autoreleasepool降低記憶體壓力
        return autoreleasepool { () -> [DiffChange] in
            var result = [DiffChange]()
            result.reserveCapacity(diff.count) // 預先分配容量
            
            var currentEqual = ""
            var currentInsert = ""
            var currentDelete = ""
            
            // 合併差異函數，將當前累積的變更添加到結果
            let mergeChanges = {
                // 清理不必要的空字串
                if !currentEqual.isEmpty {
                    result.append(.equal(currentEqual))
                    currentEqual = ""
                }
                
                // 特殊處理：如果刪除和插入部分相同，將它們視為相等部分
                if currentDelete == currentInsert && !currentDelete.isEmpty {
                    result.append(.equal(currentDelete))
                } else {
                    // 處理刪除和插入部分
                    if !currentDelete.isEmpty {
                        result.append(.delete(currentDelete))
                    }
                    if !currentInsert.isEmpty {
                        result.append(.insert(currentInsert))
                    }
                }
                
                // 清空累積的變更
                currentDelete = ""
                currentInsert = ""
            }
            
            // 遍歷所有差異，合併相鄰的同類變更
            for change in diff {
                switch change {
                case .equal(let text):
                    // 如果有累積的插入或刪除，先處理它們
                    if !currentInsert.isEmpty || !currentDelete.isEmpty {
                        mergeChanges()
                    }
                    // 累積相等部分
                    currentEqual += text
                    
                case .insert(let text):
                    // 如果有累積的相等部分，先添加到結果
                    if !currentEqual.isEmpty {
                        result.append(.equal(currentEqual))
                        currentEqual = ""
                    }
                    // 累積插入部分
                    currentInsert += text
                    
                case .delete(let text):
                    // 如果有累積的相等部分，先添加到結果
                    if !currentEqual.isEmpty {
                        result.append(.equal(currentEqual))
                        currentEqual = ""
                    }
                    // 累積刪除部分
                    currentDelete += text
                }
            }
            
            // 處理剩餘的累積變更
            if !currentEqual.isEmpty {
                result.append(.equal(currentEqual))
            } else if !currentInsert.isEmpty || !currentDelete.isEmpty {
                mergeChanges()
            }
            
            return result
        }
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
    
    // 優化差異函數以改善記憶體管理
    static func diffStrings(_ old: String, _ new: String) -> [DiffChange] {
        if old.isEmpty && new.isEmpty { return [] }
        if old.isEmpty { return [.insert(new)] }
        if new.isEmpty { return [.delete(old)] }
        if old == new { return [.equal(old)] }
        
        // 使用高效能的字串比較，避免過多的記憶體分配
        var result = [DiffChange]()
        
        // 改進：預先分配容量，減少記憶體重分配
        result.reserveCapacity(max(old.count, new.count) / 5) // 粗估字元變更數
        
        // 使用autoreleasepool確保中間字串及時釋放
        autoreleasepool {
            let oldChars = Array(old)
            let newChars = Array(new)
            
            // 創建動態規劃表
            var dp = [[Int]](repeating: [Int](repeating: 0, count: newChars.count + 1), count: oldChars.count + 1)
            
            // 填充dp表
            for i in 0...oldChars.count {
                for j in 0...newChars.count {
                    if i == 0 {
                        dp[i][j] = j
                    } else if j == 0 {
                        dp[i][j] = i
                    } else if oldChars[i-1] == newChars[j-1] {
                        dp[i][j] = dp[i-1][j-1]
                    } else {
                        dp[i][j] = min(dp[i-1][j], dp[i][j-1]) + 1
                    }
                }
            }
            
            // 回溯找出差異
            var i = oldChars.count
            var j = newChars.count
            
            var currentEqual = ""
            var currentDelete = ""
            var currentInsert = ""
            
            // 使用回溯法找出最短編輯序列
            while i > 0 || j > 0 {
                if i > 0 && j > 0 && oldChars[i-1] == newChars[j-1] {
                    // 相同字元
                    currentEqual = String(oldChars[i-1]) + currentEqual
                    i -= 1
                    j -= 1
                } else {
                    // 提交當前累積的相同部分
                    if !currentEqual.isEmpty {
                        result.insert(.equal(currentEqual), at: 0)
                        currentEqual = ""
                    }
                    
                    if j > 0 && (i == 0 || dp[i][j-1] <= dp[i-1][j]) {
                        // 插入操作
                        currentInsert = String(newChars[j-1]) + currentInsert
                        j -= 1
                    } else if i > 0 {
                        // 刪除操作
                        currentDelete = String(oldChars[i-1]) + currentDelete
                        i -= 1
                    }
                    
                    // 檢查是否需要提交當前累積的插入/刪除部分
                    if (i > 0 && j > 0 && oldChars[i-1] == newChars[j-1]) || (i == 0 && j == 0) {
                        if !currentDelete.isEmpty {
                            result.insert(.delete(currentDelete), at: 0)
                            currentDelete = ""
                        }
                        if !currentInsert.isEmpty {
                            result.insert(.insert(currentInsert), at: 0)
                            currentInsert = ""
                        }
                    }
                }
            }
            
            // 處理結尾剩餘部分
            if !currentEqual.isEmpty {
                result.insert(.equal(currentEqual), at: 0)
            }
            if !currentDelete.isEmpty {
                result.insert(.delete(currentDelete), at: 0)
            }
            if !currentInsert.isEmpty {
                result.insert(.insert(currentInsert), at: 0)
            }
        }
        
        return result
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
        // 預處理文本
        let (processedOriginal, processedRewritten) = preprocessTexts(original: original, rewritten: rewritten)
        
        // 獲取差異
        let diff = diffStrings(processedOriginal, processedRewritten)
        
        // 計算插入和刪除的詞數
        var changedWordsCount = 0
        
        for change in diff {
            switch change {
            case .insert(let text), .delete(let text):
                // 根據語言特性拆分詞彙
                // 對於中文，我們以字符為單位計算
                // 對於英文和其他語言，我們以空格分隔的單詞為單位
                
                // 中文字符計數
                let chineseCharCount = text.filter { isChineseCharacter($0) }.count
                
                // 英文單詞計數
                let nonChineseText = text.filter { !isChineseCharacter($0) }
                let words = nonChineseText.split(separator: " ")
                let wordCount = words.count
                
                // 合計詞數變化
                changedWordsCount += chineseCharCount + wordCount
            case .equal:
                // 相等部分不計入變更
                break
            }
        }
        
        return changedWordsCount
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
