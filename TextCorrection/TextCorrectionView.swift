import SwiftUI
import os.log
import AppKit

// 已經從其他地方導入 NSColor 擴展，不需要在這裡重複定義
// fileprivate extension NSColor {
//     convenience init?(hexString: String) {
//         let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
//         var int = UInt64()
//         Scanner(string: hex).scanHexInt64(&int)
//         let a, r, g, b: UInt64
//         switch hex.count {
//         case 3: // RGB (12-bit)
//             (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
//         case 6: // RGB (24-bit)
//             (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
//         case 8: // ARGB (32-bit)
//             (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
//         default:
//             return nil
//         }
//         self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
//     }
// }

/// 顯示文本差異的NSViewRepresentable包裝器
struct TextDifferenceView: NSViewRepresentable, @unchecked Sendable {
    var originalText: String
    var correctedText: String
    
    // 日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextDifferenceView")
    
    func makeNSView(context: Context) -> NSScrollView {
        logger.debug("建立文本差異視圖")
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 15, height: 15)
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.white
        textView.isRichText = true
        
        // 允許選擇但不顯示插入點
        textView.isSelectable = true
        textView.isFieldEditor = false
        
        // 適當的字體設置
        let font = NSFont.systemFont(ofSize: 22)
        textView.font = font
        
        // 設置行間距
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping
        textView.defaultParagraphStyle = paragraphStyle
        
        // 設置文本容器以正確換行
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            logger.error("無法取得文本視圖")
            return
        }
        
        logger.debug("更新文本差異視圖內容")
        
        if originalText.isEmpty && correctedText.isEmpty {
            textView.string = "尚無文本校正結果"
            return
        }
        
        // 使用TextProcessing處理文本差異
        let attributedString = TextProcessing.compareTexts(
            original: originalText,
            rewritten: correctedText,
            customFont: NSFont.systemFont(ofSize: 22)
        )
        
        DispatchQueue.main.async {
            textView.textStorage?.setAttributedString(attributedString)
        }
    }
}

/// 主文本校正視圖
struct TextCorrectionView: View, @unchecked Sendable {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false
    @State private var showCopySuccessIndicator = false
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextCorrectionView")
    
    var body: some View {
        VStack(spacing: 0) {
            // 頂部工具列
            HStack {
                Text("AI 潤飾")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    logger.debug("設置按鈕被點擊")
                    showSettings()
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.9)))
            
            // 主要內容區域
            ZStack {
                // 背景漸變
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.9)),
                        Color(NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.9))
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                VStack(spacing: 15) {
                    // 文本顯示區域
                    if appState.isProcessing {
                        ProgressView(value: appState.processingProgress) {
                            Text("處理中...")
                                .foregroundColor(.white)
                        }
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding()
                    } else if !appState.errorMessage.isEmpty {
                        Text("發生錯誤：\(appState.errorMessage)")
                            .foregroundColor(.red)
                            .padding()
                    } else if !appState.correctedText.isEmpty {
                        TextDifferenceView(
                            originalText: appState.originalText,
                            correctedText: appState.correctedText
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.8)))
                        .cornerRadius(10)
                        .padding([.horizontal, .top])
                    } else {
                        Text("尚無文本校正結果")
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.8)))
                            .cornerRadius(10)
                            .padding([.horizontal, .top])
                    }
                    
                    // 底部狀態區
                    HStack {
                        Text("字元數: \(appState.characterCount)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text("⌘+C 複製文字")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    // 底部操作區
                    HStack {
                        Spacer()
                        
                        ZStack {
                            Button("複製並貼上") {
                                logger.debug("複製並貼上按鈕被點擊")
                                copyAndPaste()
                                
                                // 顯示複製成功指示
                                withAnimation {
                                    showCopySuccessIndicator = true
                                }
                                
                                // 3秒後自動隱藏
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        showCopySuccessIndicator = false
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(NSColor(red: 0.16, green: 0.15, blue: 0.18, alpha: 0.95)))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            
                            // 複製成功指示
                            if showCopySuccessIndicator {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                                    .offset(x: -75, y: 0)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        
                        Text("⏎")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .padding(.trailing, 10)
                    }
                    .padding()
                    .background(Color(NSColor(red: 0.16, green: 0.15, blue: 0.18, alpha: 0.95)))
                }
            }
        }
        .frame(width: 500, height: 300)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .onAppear {
            logger.debug("TextCorrectionView 出現")
            // 更新窗口狀態
            updateWindowState(isOpen: true)
        }
        .onDisappear {
            logger.debug("TextCorrectionView 消失")
            // 更新窗口狀態
            updateWindowState(isOpen: false)
        }
    }
    
    // 顯示設置窗口
    private func showSettings() {
        logger.debug("顯示設置窗口")
        showingSettings = true
        appState.isSettingsWindowOpen = true
    }
    
    // 更新窗口狀態
    private func updateWindowState(isOpen: Bool) {
        appState.isTextWindowOpen = isOpen
        logger.debug("文本窗口狀態更新為: \(isOpen)")
        // AppKitBridge.shared.notifyWindowStateChanged(type: "text", isVisible: isOpen)
    }
    
    // 複製並貼上功能
    private func copyAndPaste() {
        logger.debug("執行複製並貼上操作")
        // AppKitBridge.shared.copyAndPasteCorrectedText()
        
        // 臨時實現，直接複製文本
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.correctedText, forType: .string)
        logger.debug("文本已複製到剪貼板")
        #endif
    }
}

#Preview {
    TextCorrectionView()
        .environmentObject(AppState.shared)
} 