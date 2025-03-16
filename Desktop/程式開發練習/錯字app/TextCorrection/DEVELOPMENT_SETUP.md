# TextCorrection 開發環境配置

本文檔詳細說明 TextCorrection 應用的開發環境配置，包括本地環境搭建步驟、必要依賴項和版本以及常見問題的解決方案。

## 開發環境要求

### 基本要求

- **macOS** 13.0 或更高版本
- **Xcode** 15.0 或更高版本
- **Swift** 5.9 或更高版本
- **Git** 2.30.0 或更高版本

### 硬體推薦

- Mac 運行 Apple Silicon 或 Intel 處理器
- 至少 8GB RAM
- 至少 20GB 可用硬碟空間（用於 Xcode 和專案）

## 安裝步驟

### 1. 安裝 Xcode

1. 從 Mac App Store 下載並安裝 Xcode
2. 首次啟動 Xcode 時，同意許可協議並等待安裝附加組件
3. 安裝命令行工具：
   ```bash
   xcode-select --install
   ```

### 2. 克隆專案

```bash
# 克隆專案到本地
git clone https://github.com/yourusername/TextCorrection.git
cd TextCorrection

# 確保你在 main 分支上
git checkout main
```

### 3. 設置依賴項

TextCorrection 使用 Swift Package Manager (SPM) 管理依賴項。開啟 Xcode 專案後，SPM 會自動解析和下載所需依賴。

### 4. 配置開發證書

1. 在 Xcode 中打開 TextCorrection.xcodeproj
2. 進入 "Signing & Capabilities" 標籤
3. 選擇你的 Apple Developer 賬號
4. 勾選 "Automatically manage signing"

### 5. 選擇 Scheme 並構建專案

1. 在 Xcode 頂部工具欄選擇 "TextCorrection" scheme
2. 選擇 "My Mac" 作為目標裝置
3. 點擊執行按鈕 (⌘+R) 構建並運行專案

## 依賴項

### 核心依賴項

| 依賴項 | 版本 | 用途 |
|-------|------|-----|
| Differ | 1.4.6 | 用於文本差異比較 |
| DifferenceKit | 1.3.0 | 增強的差異計算工具 |
| HotKey | `main` (a3cf605) | 用於全局熱鍵管理 |
| KeychainAccess | `master` (e0c7...) | 安全存儲 API 密鑰 |
| PythonKit | `master` (6fee761) | Python 互操作能力 |

### 依賴項詳情

#### Differ & DifferenceKit

這兩個庫用於實現高效的文本差異比較。在 TextProcessing 類中使用這些庫來識別原始文本和校正文本之間的差異。

```swift
// 使用示例
import Differ

let diff = diff(originalText, correctedText)
```

#### HotKey

用於註冊和處理全局熱鍵。應用使用 HotKey 監聽預定義的快捷鍵組合，觸發文本校正功能。

```swift
// 使用示例
import HotKey

let hotKey = HotKey(key: .space, modifiers: [.command, .shift])
hotKey.keyDownHandler = { /* 處理熱鍵事件 */ }
```

#### KeychainAccess

用於安全存儲 API 密鑰和其他敏感信息。

```swift
// 使用示例
import KeychainAccess

let keychain = Keychain(service: "com.yourcompany.TextCorrection")
keychain["apiKey"] = "your-api-key"
```

#### PythonKit

提供與 Python 庫的互操作能力（如果需要使用 Python 中的 NLP 庫）。

```swift
// 使用示例
import PythonKit

let sys = Python.import("sys")
let nltkModule = Python.import("nltk")
```

## 專案結構

```
TextCorrection/
├── TextCorrection/
│   ├── AppDelegate.swift        # 應用委託和主要控制邏輯
│   ├── TextCorrectionApp.swift  # SwiftUI 應用入口點
│   ├── AppKitBridge.swift       # AppKit 和 SwiftUI 的橋接層
│   ├── Models/                  # 數據模型
│   ├── Views/                   # SwiftUI 視圖
│   │   ├── TextCorrectionView.swift   # 主視圖
│   │   ├── SettingsView.swift         # 設置視圖
│   │   └── Components/                # 可重用 UI 組件
│   ├── Managers/                # 系統功能管理
│   │   ├── PasteboardManager.swift   # 剪貼板監控
│   │   ├── HotKeyManager.swift       # 熱鍵管理
│   │   └── StatusItemManager.swift   # 狀態欄圖標管理
│   ├── Services/                # 業務邏輯服務
│   │   ├── TextProcessing.swift      # 文本處理邏輯
│   │   └── OpenAIService.swift       # API 通信服務
│   └── Utils/                   # 工具類和擴展
├── TextCorrection.xcodeproj/    # Xcode 專案文件
├── TextCorrectionTests/         # 單元測試
└── TextCorrectionUITests/       # UI 測試
```

## 開發工作流程

### 1. 選擇要開發的任務

從 SCRATCHPAD.md 或專案管理工具中選擇一個任務。

### 2. 創建分支

```bash
git checkout -b feature/your-feature-name
```

### 3. 開發與測試

1. 實現功能或修復錯誤
2. 編寫單元測試
3. 確保現有測試通過

### 4. 提交更改

```bash
git add .
git commit -m "描述你的更改"
```

### 5. 推送分支

```bash
git push origin feature/your-feature-name
```

## 運行與調試

### 執行應用程序

在 Xcode 中按 ⌘+R 運行應用程序，或點擊工具欄中的播放按鈕。

### 調試

1. 設置斷點 - 點擊代碼行號旁邊設置斷點
2. 使用 ⌘+R 運行應用程序
3. 使用調試控制台和變量檢查器檢查狀態

### 日誌記錄

應用使用 `os.log` 進行日誌記錄。查看控制台應用程序中的日誌：

1. 打開控制台應用程序（Applications/Utilities/Console）
2. 在搜索欄中輸入 "TextCorrection"
3. 查看過濾後的日誌消息

## 常見問題解決方案

### 1. Xcode 無法找到項目的 scheme

**問題：** Xcode 播放按鈕灰色顯示，無法運行項目。

**解決方案：**
1. 選擇產品 > Scheme > 新建 Scheme
2. 選擇 TextCorrection 作為目標
3. 確保勾選「共享」選項
4. 點擊「確定」，新的 scheme 應該可用

### 2. 依賴包解析失敗

**問題：** SPM 無法解析或下載依賴項。

**解決方案：**
1. 文件 > 套件 > 解析套件版本
2. 如果仍然失敗，手動刪除 derived data：
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
3. 重新啟動 Xcode 並再次嘗試

### 3. 熱鍵功能不工作

**問題：** 設置的熱鍵無法觸發功能。

**解決方案：**
1. 確保在系統偏好設定 > 安全性與隱私權 > 輔助使用中已授權應用程序
2. 檢查其他應用程序是否使用了相同的熱鍵
3. 嘗試使用不同的熱鍵組合
4. 在 `HotKeyManager.swift` 中添加日誌以診斷問題

### 4. 執行時出現 EXC_BAD_ACCESS 錯誤

**問題：** 應用程序運行時崩潰，顯示 EXC_BAD_ACCESS 錯誤。

**解決方案：**
1. 啟用 Xcode 的地址消毒工具：編輯 scheme > 診斷 > 啟用地址消毒
2. 檢查類中的弱引用是否被正確標記
3. 檢查在非同步操作完成後是否存在對已釋放對象的訪問
4. 對於 AppDelegate 和管理器類，確保生命週期管理正確

### 5. 文本處理邏輯不正確

**問題：** 文本差異顯示不正確或丟失。

**解決方案：**
1. 啟用更詳細的日誌記錄以跟踪文本處理流程
2. 在 `TextProcessing.swift` 中添加測試代碼來驗證比較邏輯
3. 確保換行符被正確處理
4. 檢查預處理和後處理步驟

## 效能提示

1. **使用 Instruments 分析性能**
   - Product > Profile (⌘+I) 啟動 Instruments
   - 使用 Time Profiler 工具識別高 CPU 使用率的方法

2. **進行調試建置**
   - 選擇 Product > Build For > Profiling 創建優化的調試構建

3. **優化 UI 更新**
   - 限制 UI 更新頻率，特別是在處理進度顯示方面
   - 使用防跳變技術，避免短時間內多次觸發 UI 更新

## 文檔指南

主要文檔文件：

1. **ARCHITECTURE.md** - 架構設計和模組關係
2. **DEPENDENCIES.md** - 依賴項和引用關係
3. **STATE_MANAGEMENT.md** - 狀態管理策略
4. **TESTING_STRATEGY.md** - 測試策略和方法
5. **CORE_FUNCTIONS.md** - 核心功能說明
6. **SCRATCHPAD.md** - 開發筆記和問題追踪

## 其他資源

- [Swift 官方文檔](https://swift.org/documentation/)
- [SwiftUI 文檔](https://developer.apple.com/documentation/swiftui)
- [AppKit 文檔](https://developer.apple.com/documentation/appkit)
- [HotKey GitHub 倉庫](https://github.com/soffes/HotKey)
- [Differ GitHub 倉庫](https://github.com/tonyarnold/Differ) 