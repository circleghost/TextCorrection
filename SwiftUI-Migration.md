# TextCorrection SwiftUI 遷移計畫

## 遷移目標

將 TextCorrection 應用從 AppKit (Cocoa) 架構逐步遷移到現代化的 SwiftUI 架構，以獲得更好的開發效率、維護性和使用者體驗。

## 現狀分析 (2023 年)

目前專案主要使用 AppKit (Cocoa) 架構，包括：
- NSWindow 和 NSView 構建的 UI
- AppDelegate 作為主要協調器
- 傳統的 MVC 架構

## 遷移階段

### 第一階段：基礎設施準備 (進行中)

- [ ] 建立 SwiftUI 預覽支援
- [ ] 創建應用狀態管理系統
- [ ] 設計 UserDefaults 與 AppStorage 整合

### 第二階段：UI 元素遷移

- [ ] 設定視窗遷移至 SwiftUI
- [ ] 創建 SwiftUI 和 AppKit 的橋接層
- [ ] 更新 AppDelegate 以支援 SwiftUI 生命週期

### 第三階段：文本校正視窗遷移

- [ ] 創建 SwiftUI 文本校正視圖
- [ ] 實現差異對比功能
- [ ] 整合 SwiftUI 動畫與特效

### 第四階段：核心功能遷移

- [ ] 重構 OpenAI 服務以支援 SwiftUI
- [ ] 使用 Combine 框架處理異步操作
- [ ] 實現 SwiftUI 狀態同步機制

### 第五階段：完整遷移與優化

- [ ] 移除遺留的 AppKit 代碼
- [ ] 完善 SwiftUI 生命週期管理
- [ ] 適配黑暗模式與系統樣式
- [ ] 進行性能優化

## 技術決策

1. **混合架構階段**：在遷移過程中，將使用 NSHostingController 在 AppKit 視窗中嵌入 SwiftUI 視圖
2. **狀態管理**：使用 ObservableObject 協議管理應用狀態
3. **數據持久化**：使用 @AppStorage 替代直接訪問 UserDefaults

## 遷移進度追蹤

| 元件 | 狀態 | 開始日期 | 完成日期 | 備註 |
|-----|-----|---------|---------|-----|
| 設定視窗 | 計畫中 | - | - | 優先度最高 |
| 文本校正視窗 | 未開始 | - | - | - |
| OpenAI 服務 | 未開始 | - | - | - |
| 狀態欄功能 | 未開始 | - | - | - |
| 快捷鍵管理 | 未開始 | - | - | - |

## 風險評估

1. **性能隱憂**：SwiftUI 在處理大量文本差異顯示時可能存在性能問題
2. **兼容性**：需確保支援 macOS 11.0+ 
3. **功能限制**：某些 AppKit 特有功能在 SwiftUI 中可能難以實現

## 參考資源

- [Apple SwiftUI 文檔](https://developer.apple.com/documentation/swiftui)
- [Bridging AppKit and SwiftUI](https://www.hackingwithswift.com/quick-start/swiftui/how-to-integrate-swiftui-with-appkit)
- [Migrating from Cocoa to SwiftUI](https://www.swiftbysundell.com/articles/getting-started-with-swiftui/) 