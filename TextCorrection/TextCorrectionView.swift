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
struct TextDifferenceView: NSViewRepresentable {
    var originalText: String
    var correctedText: String
    
    // 日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextDifferenceView")
    
    func makeNSView(context: Context) -> NSScrollView {
        logger.debug("建立文本差異視圖")
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        
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
        
        // 啟用用戶交互
        textView.allowsDocumentBackgroundColorChange = false
        textView.allowsCharacterPickerTouchBarItem = true
        textView.allowsUndo = true
        
        // 適當的字體設置
        let font = NSFont.systemFont(ofSize: 22)
        textView.font = font
        
        // 設置行間距
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping
        textView.defaultParagraphStyle = paragraphStyle
        
        // 設置文本容器以正確換行和滾動
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
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
            
            // 確保文本視圖正確調整大小以顯示所有內容
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            
            // 強制重新計算佈局
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            
            // 確保滾動視圖反映內容變化
            scrollView.reflectScrolledClipView(scrollView.contentView)
            
            // 滾動到頂部
            scrollView.contentView.scroll(to: NSPoint.zero)
        }
    }
}

/// 流光特效視圖
struct FlowingGlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // 根據高品質效果設定調整流光數量
            let glowCount = appState.isHighQualityEffectsEnabled ? 5 : 3
            ForEach(0..<glowCount, id: \.self) { i in
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.7, blue: 0.9, opacity: appState.isHighQualityEffectsEnabled ? 0.7 : 0.5),
                                Color(red: 0.5, green: 0.3, blue: 0.9, opacity: appState.isHighQualityEffectsEnabled ? 0.4 : 0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: appState.isHighQualityEffectsEnabled ? 25 : 15)
                    .offset(
                        x: animate ? CGFloat.random(in: -120...120) : CGFloat.random(in: -180...180),
                        y: animate ? CGFloat.random(in: -70...70) : CGFloat.random(in: -120...120)
                    )
                    .animation(
                        appState.isAnimationsEnabled ? 
                        Animation.easeInOut(duration: Double.random(in: 4...7))
                            .repeatForever(autoreverses: true)
                            .delay(Double.random(in: 0...2)) : .none,
                        value: animate
                    )
            }
        }
        .clipped()
        .drawingGroup() // 使用Metal渲染以提高性能
        .onAppear {
            animate = appState.isAnimationsEnabled
        }
    }
}

/// 粒子特效視圖
struct ParticleEffectView: View {
    @EnvironmentObject private var appState: AppState
    
    @State private var particles: [Particle] = []
    @State private var timer: Timer?
    
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var size: CGFloat
        var opacity: Double
        var rotation: Double
        var color: Color
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 只有啟用粒子效果時才顯示
                if appState.isParticleEffectsEnabled {
                    ForEach(particles) { particle in
                        Image(systemName: "sparkle")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(particle.color)
                            .frame(width: particle.size, height: particle.size)
                            .position(particle.position)
                            .opacity(particle.opacity)
                            .rotationEffect(.degrees(particle.rotation))
                    }
                }
            }
            .onAppear {
                // 開始生成粒子
                if appState.isParticleEffectsEnabled {
                    startGeneratingParticles(in: geometry.size)
                }
            }
            .onDisappear {
                // 停止生成粒子
                timer?.invalidate()
                timer = nil
            }
            .onChange(of: appState.isParticleEffectsEnabled) { _, newValue in
                if newValue {
                    startGeneratingParticles(in: geometry.size)
                } else {
                    timer?.invalidate()
                    timer = nil
                    particles = []
                }
            }
        }
    }
    
    private func startGeneratingParticles(in size: CGSize) {
        // 清除現有計時器
        timer?.invalidate()
        
        // 根據設定調整粒子生成頻率
        let interval = appState.isHighQualityEffectsEnabled ? 0.3 : 0.5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            if appState.isAnimationsEnabled {
                withAnimation {
                    addParticle(in: size)
                    
                    // 移除不可見的粒子
                    particles = particles.filter { $0.opacity > 0 }
                }
            } else {
                addParticle(in: size)
                particles = particles.filter { $0.opacity > 0 }
            }
        }
        
        // 初始生成一些粒子
        for _ in 0..<8 {
            addParticle(in: size)
        }
    }
    
    private func addParticle(in size: CGSize) {
        // 在隨機位置生成粒子
        let newParticle = Particle(
            position: CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            ),
            size: CGFloat.random(in: 12...22),
            opacity: Double.random(in: 0.5...0.9),
            rotation: Double.random(in: 0...360),
            color: [
                Color(red: 0.5, green: 0.7, blue: 1.0),
                Color(red: 0.8, green: 0.6, blue: 1.0),
                Color(red: 1.0, green: 0.7, blue: 0.5),
                Color(red: 0.4, green: 0.8, blue: 0.9)
            ].randomElement()!
        )
        
        particles.append(newParticle)
        
        // 根據動畫設定添加動畫效果
        if appState.isAnimationsEnabled {
            withAnimation(Animation.linear(duration: Double.random(in: 2...5))) {
                if let index = particles.firstIndex(where: { $0.id == newParticle.id }) {
                    particles[index].opacity = 0
                    particles[index].position.y -= CGFloat.random(in: 30...70)
                    particles[index].rotation += Double.random(in: 180...360)
                }
            }
        } else {
            // 無動畫模式下立即設定最終狀態
            if let index = particles.firstIndex(where: { $0.id == newParticle.id }) {
                particles[index].opacity = 0
                particles[index].position.y -= CGFloat.random(in: 30...70)
                particles[index].rotation += Double.random(in: 180...360)
            }
        }
    }
}

/// 主文本校正視圖
struct TextCorrectionView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false
    @State private var showCopySuccessIndicator = false
    @State private var isTextVisible = false
    @State private var showParticles = false
    
    // 添加日誌支持
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextCorrectionView")
    
    var body: some View {
        VStack(spacing: 0) {
            // 頂部工具列
            HStack {
                Text("文本校正")
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
                
                // 僅當啟用視覺效果時顯示流光效果
                if appState.isVisualEffectsEnabled {
                    FlowingGlowView()
                        .environmentObject(appState)
                        .opacity(0.35)
                }
                
                VStack(spacing: 15) {
                    // 文本顯示區域
                    if appState.isProcessing {
                        ProgressView(value: appState.processingProgress) {
                            Text("處理中...")
                                .foregroundColor(.white)
                        }
                        .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.4, green: 0.6, blue: 0.9)))
                        .padding()
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appState.processingProgress)
                    } else if !appState.errorMessage.isEmpty {
                        Text("發生錯誤：\(appState.errorMessage)")
                            .foregroundColor(.red)
                            .padding()
                            .transition(.scale.combined(with: .opacity))
                    } else if !appState.correctedText.isEmpty {
                        GeometryReader { geometry in
                            ZStack {
                                TextDifferenceView(
                                    originalText: appState.originalText,
                                    correctedText: appState.correctedText
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.8)))
                                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                                )
                                .padding([.horizontal, .top])
                                .opacity(isTextVisible ? 1 : 0)
                                .animation(appState.isAnimationsEnabled ? .easeIn(duration: 0.5) : .none, value: isTextVisible)
                                .onAppear {
                                    if appState.isAnimationsEnabled {
                                        withAnimation {
                                            isTextVisible = true
                                        }
                                    } else {
                                        isTextVisible = true
                                    }
                                    showParticles = appState.isParticleEffectsEnabled
                                }
                                
                                // 粒子效果層
                                if showParticles {
                                    ParticleEffectView()
                                        .environmentObject(appState)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
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
                        // 為底部區域添加光暈效果
                        if appState.isVisualEffectsEnabled && !appState.correctedText.isEmpty {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [Color(red: 0.3, green: 0.5, blue: 0.9, opacity: 0.5), Color.clear]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 160, height: 60)
                                .blur(radius: 12)
                                .offset(x: -40, y: 0)
                        }
                        
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
                                
                                // 如果粒子效果已啟用，顯示粒子效果爆發
                                if appState.isParticleEffectsEnabled {
                                    // 此處可以添加特殊的粒子爆發效果
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.18, green: 0.17, blue: 0.2),
                                                Color(red: 0.16, green: 0.15, blue: 0.18)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            )
                            .foregroundColor(.white)
                            
                            // 複製成功指示
                            if showCopySuccessIndicator {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 16))
                                    
                                    Text("已複製!")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
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
        .frame(minWidth: 500, minHeight: 300)
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
            
            // 重置動畫狀態
            isTextVisible = false
            showParticles = false
        }
    }
    
    // 顯示設置窗口
    private func showSettings() {
        logger.debug("顯示設置窗口")
        // 改用AppKitBridge統一調用設定窗口
        AppKitBridge.shared.showSettingsWindow()
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