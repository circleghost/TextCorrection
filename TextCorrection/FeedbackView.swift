import SwiftUI
import os.log

/// 反饋類型枚舉
enum FeedbackType: String, CaseIterable, Identifiable {
    case bug = "錯誤報告"
    case feature = "功能建議"
    case usability = "使用體驗問題"
    case other = "其他"
    
    var id: String { self.rawValue }
}

/// 反饋表單視圖
struct FeedbackView: View {
    // 環境參數
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var appState: AppState
    
    // 日誌
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "FeedbackView")
    
    // 表單狀態
    @State private var feedbackType: FeedbackType = .bug
    @State private var feedbackText: String = ""
    @State private var contactEmail: String = ""
    @State private var includeSystemInfo: Bool = true
    @State private var includeScreenshot: Bool = false
    
    // 提交狀態
    @State private var isSubmitting: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    // 字元計數
    private var characterCount: Int {
        feedbackText.count
    }
    private let maxCharacterCount = 1000
    
    var body: some View {
        VStack(spacing: 0) {
            // 標題
            Text("提交反饋")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 16)
                .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 反饋類型選擇
                    VStack(alignment: .leading, spacing: 8) {
                        Text("反饋類型")
                            .font(.headline)
                        
                        Picker("反饋類型", selection: $feedbackType) {
                            ForEach(FeedbackType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(.top, 16)
                    
                    // 反饋內容輸入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("您的反饋")
                            .font(.headline)
                        
                        ZStack(alignment: .bottomTrailing) {
                            TextEditor(text: $feedbackText)
                                .font(.body)
                                .frame(minHeight: 100, maxHeight: 200)
                                .padding(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            
                            Text("\(characterCount)/\(maxCharacterCount)")
                                .font(.caption)
                                .foregroundColor(characterCount > maxCharacterCount ? .red : .gray)
                                .padding(8)
                                .zIndex(1)
                        }
                        
                        if characterCount > maxCharacterCount {
                            Text("反饋內容超過字數限制")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    // 聯絡郵箱
                    VStack(alignment: .leading, spacing: 8) {
                        Text("聯絡郵箱（選填）")
                            .font(.headline)
                        
                        TextField("請輸入您的郵箱地址", text: $contactEmail)
                            .font(.body)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disableAutocorrection(true)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            #endif
                    }
                    
                    // 附加信息選項
                    VStack(alignment: .leading, spacing: 12) {
                        Text("附加信息")
                            .font(.headline)
                        
                        Toggle("包含系統信息", isOn: $includeSystemInfo)
                            .font(.body)
                        
                        Toggle("包含螢幕截圖", isOn: $includeScreenshot)
                            .font(.body)
                    }
                    
                    // 隱私提示
                    Text("注意：所有提交的內容都將用於改進應用。我們不會將您的個人信息用於其他用途。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
            }
            
            Divider()
            
            // 按鈕區域
            HStack(spacing: 16) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("取消")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    submitFeedback()
                }) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("提交")
                            .bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmittingDisabled)
            }
            .padding(16)
        }
        .frame(width: 480, height: 580)
        .alert("提交成功", isPresented: $showSuccessAlert) {
            Button("確定") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("感謝您的反饋，我們會認真處理您提供的信息。")
        }
        .alert("提交失敗", isPresented: $showErrorAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // 禁用提交按鈕的條件
    private var isSubmittingDisabled: Bool {
        feedbackText.isEmpty || 
        characterCount > maxCharacterCount ||
        isSubmitting
    }
    
    // 提交反饋
    private func submitFeedback() {
        // 防止重複提交
        guard !isSubmitting else { return }
        
        // 開始提交
        isSubmitting = true
        logger.debug("正在提交反饋...")
        
        // 收集系統信息
        var systemInfo = ""
        if includeSystemInfo {
            systemInfo = collectSystemInfo()
        }
        
        // 準備反饋數據
        let feedback = FeedbackData(
            type: feedbackType.rawValue,
            content: feedbackText,
            email: contactEmail,
            systemInfo: includeSystemInfo ? systemInfo : nil,
            screenshot: includeScreenshot ? "將在這裡添加截圖" : nil
        )
        
        // 記錄到日誌
        logger.debug("反饋類型: \(feedback.type)")
        
        // 模擬提交過程
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // 測試版階段，只記錄到日誌中
            logger.info("收到反饋: \(self.feedbackText)")
            
            // 重置狀態
            self.isSubmitting = false
            self.showSuccessAlert = true
            
            // 模擬儲存反饋
            saveFeedbackToFile(feedback)
        }
    }
    
    // 收集系統信息
    private func collectSystemInfo() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let deviceName = Host.current().localizedName ?? "未知裝置"
        
        return """
        設備: \(deviceName)
        系統: \(osVersion)
        App版本: \(appVersion)
        """
    }
    
    // 將反饋保存到文件（測試階段使用）
    private func saveFeedbackToFile(_ feedback: FeedbackData) {
        // 建立文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "feedback_\(dateString).txt"
        
        // 建立文件路徑
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let feedbacksDirectory = documentsDirectory.appendingPathComponent("Feedbacks")
        let fileURL = feedbacksDirectory.appendingPathComponent(fileName)
        
        // 確保目錄存在
        do {
            try FileManager.default.createDirectory(at: feedbacksDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("無法創建反饋目錄: \(error.localizedDescription)")
            return
        }
        
        // 準備反饋內容
        let content = """
        時間: \(Date())
        類型: \(feedback.type)
        內容: \(feedback.content)
        郵箱: \(feedback.email)
        系統信息: \(feedback.systemInfo ?? "未提供")
        截圖: \(feedback.screenshot != nil ? "包含" : "未提供")
        """
        
        // 寫入文件
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.debug("已保存反饋到文件: \(fileURL.path)")
        } catch {
            logger.error("保存反饋到文件失敗: \(error.localizedDescription)")
        }
    }
}

/// 反饋數據結構
struct FeedbackData {
    let type: String
    let content: String
    let email: String
    let systemInfo: String?
    let screenshot: String?
    let timestamp = Date()
}

#Preview {
    FeedbackView()
        .environmentObject(AppState.shared)
} 