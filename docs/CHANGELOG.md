# Changelog

本文件記錄 TextCorrection 應用的所有重要變更。

## [未發佈]

### 添加
- 創建 AppKitBridge 類作為 AppKit 和 SwiftUI 之間的通信橋樑
- 擴展 AppState 類，添加更多狀態管理功能
- 整合 os.log 日誌系統，提升調試能力
- 實現 Combine 框架的響應式狀態同步
- 添加應用內通知系統

### 修改
- 重構 PasteboardManager，使用 AppKitBridge 通知剪貼板變化
- 重構 HotKeyManager，與 AppState 整合熱鍵配置
- 優化 SwiftUI 視圖（TextCorrectionView 和 SettingsView）以使用共享狀態
- 開始 SwiftUI 遷移計畫
- 創建 SwiftUI 遷移文檔

### 修復
- 修復設定視窗顯示問題
- 解決 AppKit 視圖樣式衝突
- 改進窗口關閉處理邏輯，避免內存洩漏
- 🐛 修復字體相關崩潰問題
  - 將界面元素統一使用粉圓體
  - 解決FontManager執行緒安全問題
  - 優化字體載入流程，防止SIGABRT崩潰

## [1.0.0] - 2023-09-16

### 添加
- 基本文本校正功能
- 使用 OpenAI API 進行智能校正
- 支援繁體中文文本校正
- 添加視覺差異對比功能
- 實現狀態欄整合
- 添加全域熱鍵支援
- 基本設定界面

## [1.0.1] - 2024-03-19

### 修復
- 🐛 修復設定視窗重複開啟問題
  - 移除多餘的設定視窗創建邏輯
  - 在AppDelegate.showSettings中添加重複開啟檢查
  - 重新設計PreferencesWindow結構

- 🐛 修復設定按鈕顯示"No Settings scene is defined"錯誤
  - 替換SettingsLink為自定義Button
  - 使用AppKitBridge.shared.showSettingsWindow()處理設定視窗開啟

- 🐛 修復TextView選擇問題
  - 完善NSTextView配置
  - 添加必要的交互設置
  - 修復acceptsFirstResponder相關問題

### 優化
- 💄 調整界面元素大小
  - 應用圖標：120x120 → 150x150
  - 主標題：36px → 42px
  - 使用方法副標題：28px → 32px
  - 指令列表圖標：32px → 40px
  - 指令標題：20px → 24px
  - 描述文字：16px → 18px
  - 按鈕文字：18px → 20px
  - 按鈕間距：水平30px → 35px，垂直12px → 14px
  - 浮動按鈕：70x70 → 80x80，圖標28px → 32px
  - 彈出視窗：寬度300px → 350px

### 技術細節
- 🔧 NSTextView配置更新：
  ```swift
  textView.isSelectable = true
  textView.allowsUndo = true
  textView.isFieldEditor = false
  textView.allowsDocumentBackgroundColorChange = false
  textView.allowsCharacterPickerTouchBarItem = true
  ```

- 🔧 設定視窗管理優化：
  - 禁用系統默認Settings場景
  - 統一使用AppKitBridge管理設定視窗
  - 優化PreferencesWindow結構 