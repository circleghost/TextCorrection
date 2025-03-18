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

## [1.0.0] - 2023-09-16

### 添加
- 基本文本校正功能
- 使用 OpenAI API 進行智能校正
- 支援繁體中文文本校正
- 添加視覺差異對比功能
- 實現狀態欄整合
- 添加全域熱鍵支援
- 基本設定界面 