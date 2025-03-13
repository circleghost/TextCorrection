import Cocoa

// 將整個類標記為 @MainActor，因為它主要處理 UI 元素
@MainActor
class TextWindowManager: @unchecked Sendable {
    weak var appDelegate: AppDelegate?
    
    // 將靜態屬性移到類別級別
    private static var lastResizeTime: TimeInterval = 0
    
    // 在類中添加新的屬性用於跟踪API完成狀態
    private var isAPICompleted = false
    private var completeResult: (originalText: String, newText: String)? = nil
    
    // 添加粉圓體字體輔助方法
    private func getPungyuFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
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
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func showTextWindow(text: String) {
        guard let appDelegate = appDelegate else { return }
        
        // 先關閉現有的文本視窗，避免重複
        if appDelegate.textWindow != nil {
            appDelegate.textWindow?.close()
            appDelegate.textWindow = nil
            // 給系統一點時間處理窗口關閉
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                self.createTextWindow(with: text)
            }
            return
        }
        
        // 如果沒有現有視窗，直接創建
        createTextWindow(with: text)
    }
    
    // 將原本的 showTextWindow 邏輯分離到一個新方法
    private func createTextWindow(with text: String) {
        guard let appDelegate = appDelegate else { return }
        
        // 確保 AppState 有原始文本
        AppState.shared.originalText = text
        
        // 同時設置 AppDelegate 的原始文本屬性
        appDelegate.originalText = text
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        // 設定視窗大小為螢幕的 50% 寬度和 25% 高度，減小初始高度
        let width = screenFrame.width * 0.5
        let height = screenFrame.height * 0.25
        let size = NSSize(width: width, height: height)
        
        // 計算視窗位置，使其位於畫面正中央
        let origin = NSPoint(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2
        )
        let windowFrame = NSRect(origin: origin, size: size)
        let adjustedFrame = screenFrame.intersection(windowFrame)
        
        appDelegate.textWindow = NSPanel(contentRect: adjustedFrame,
                     styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                     backing: .buffered, defer: false)
        appDelegate.textWindow?.title = ""
        appDelegate.textWindow?.titlebarAppearsTransparent = true
        appDelegate.textWindow?.isMovableByWindowBackground = true
        appDelegate.textWindow?.contentView?.wantsLayer = true

        // 添加漸變背景
        let gradient = CAGradientLayer()
        gradient.frame = (appDelegate.textWindow?.contentView?.bounds)!
        gradient.colors = [NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.9).cgColor,
                           NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.9).cgColor]
        gradient.locations = [0.0, 1.0]
        appDelegate.textWindow?.contentView?.layer?.addSublayer(gradient)

        appDelegate.textWindow?.isOpaque = false
        appDelegate.textWindow?.backgroundColor = .clear
        appDelegate.textWindow?.hasShadow = true
        appDelegate.textWindow?.appearance = NSAppearance(named: .darkAqua)
        
        appDelegate.textWindow?.minSize = NSSize(width: 400, height: 250)
        
        // 現代化視窗設計 - 移除標題，添加頂部裝飾條
        appDelegate.textWindow?.titleVisibility = .hidden
        appDelegate.textWindow?.titlebarAppearsTransparent = true
        
        // 創建頂部裝飾條
        let topBarView = NSView()
        topBarView.wantsLayer = true
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        
        // 添加漸變效果到頂部裝飾條
        let topBarGradient = CAGradientLayer()
        topBarGradient.colors = [
            NSColor(calibratedRed: 0.3, green: 0.6, blue: 0.9, alpha: 0.8).cgColor,  // 藍色調
            NSColor(calibratedRed: 0.5, green: 0.3, blue: 0.9, alpha: 0.8).cgColor   // 紫色調
        ]
        topBarGradient.startPoint = CGPoint(x: 0, y: 0.5)
        topBarGradient.endPoint = CGPoint(x: 1, y: 0.5)
        topBarView.layer?.addSublayer(topBarGradient)
        
        // 添加視窗控制按鈕容器，確保控制按鈕在正確位置
        let controlsContainerView = NSView()
        controlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        appDelegate.textWindow?.contentView?.addSubview(controlsContainerView)
        
        NSLayoutConstraint.activate([
            controlsContainerView.topAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.topAnchor),
            controlsContainerView.leadingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.leadingAnchor),
            controlsContainerView.heightAnchor.constraint(equalToConstant: 28),
            controlsContainerView.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        // 添加頂部裝飾條到視窗
        appDelegate.textWindow?.contentView?.addSubview(topBarView)
        
                NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: controlsContainerView.bottomAnchor, constant: -1),
            topBarView.leadingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.trailingAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 5)  // 薄的裝飾條
        ])
        
        // 設置topBarGradient的框架
        topBarGradient.frame = CGRect(x: 0, y: 0, width: appDelegate.textWindow!.frame.width, height: 5)
        
        // 創建內容視圖
        let contentView = NSView(frame: (appDelegate.textWindow?.contentView?.bounds)!)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        appDelegate.textWindow?.contentView?.addSubview(contentView)

        let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        contentView.addSubview(visualEffectView)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 主要區域
        let mainArea = NSView()
        mainArea.translatesAutoresizingMaskIntoConstraints = false
        mainArea.identifier = NSUserInterfaceItemIdentifier("mainArea")
        mainArea.wantsLayer = true
        mainArea.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.addSubview(mainArea)

        // 文字區域（圓角）
        let textContainer = NSView()
        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.wantsLayer = true
        textContainer.layer?.backgroundColor = NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.8).cgColor
        textContainer.layer?.cornerRadius = 20
        textContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        textContainer.layer?.shadowOffset = CGSize(width: 0, height: 2)
        textContainer.layer?.shadowRadius = 5
        textContainer.layer?.shadowOpacity = 1
        textContainer.identifier = NSUserInterfaceItemIdentifier("textContainer")
        mainArea.addSubview(textContainer)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textContainer.addSubview(scrollView)

        // 修改 textView 的設置
        let textView = NSTextView(frame: scrollView.bounds)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 15, height: 15)
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.white
        textView.alignment = .left
        textView.isRichText = true // 允許富文本
        
        // 設置自動調整大小和換行
        textView.autoresizingMask = [.width, .height]
        textView.isHorizontallyResizable = false // 設為 false 以跟隨視窗換行
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true // 設為 true 讓文本容器寬度跟隨視圖
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude) // 寬度為0表示自動跟隨
        
        // 設置換行模式
        textView.textContainer?.lineFragmentPadding = 5.0 // 減少行片段間的填充
        
        // 確保滾動視圖正確設置 - 增強滾動功能
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false // 禁用水平捲動，強制換行
        scrollView.autohidesScrollers = false // 始終顯示滾動條
        scrollView.verticalScrollElasticity = .allowed // 允許垂直彈性滾動
        scrollView.contentView.postsBoundsChangedNotifications = true // 發送範圍變更通知
        scrollView.borderType = .noBorder // 移除滾動視圖邊框
        
        // 添加滾動條樣式增強
        if let verticalScroller = scrollView.verticalScroller {
            verticalScroller.controlSize = .regular
            verticalScroller.knobStyle = .light // 使用淺色滾動條滑塊
        }
        
        // 確保可滾動，即使內容較少
        textView.minSize = NSSize(width: 0, height: 0) // 最小高度為0，允許文本視圖比可見範圍小
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) // 允許無限擴展
        scrollView.hasVerticalRuler = false
        scrollView.scrollerStyle = .overlay // 使用覆蓋式滾動條，更現代
        
        // 設置滾動視圖的內容大小
        let extraHeight = getPungyuFont(size: 22).boundingRectForFont.height * 3 // 額外添加3行空間
        let initialContentSize = NSSize(
            width: scrollView.bounds.width,
            height: max(scrollView.bounds.height, extraHeight)
        )
        textView.frame.size = initialContentSize
        
        // 統計信息 - 只保留統計信息，移除複製提示
        let statsContainer = NSView()
        statsContainer.translatesAutoresizingMaskIntoConstraints = false
        statsContainer.wantsLayer = true
        statsContainer.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.95).cgColor
        statsContainer.layer?.cornerRadius = 12
        statsContainer.layer?.borderWidth = 0.5
        statsContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        statsContainer.alphaValue = 0 // 初始設為隱藏
        statsContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
        statsContainer.layer?.shadowOffset = CGSize(width: 0, height: 2)
        statsContainer.layer?.shadowRadius = 8
        statsContainer.layer?.shadowOpacity = 1
        mainArea.addSubview(statsContainer)

        let statsView = NSTextField()
        statsView.translatesAutoresizingMaskIntoConstraints = false
        statsView.isEditable = false
        statsView.isBordered = false
        statsView.backgroundColor = .clear
        statsView.textColor = NSColor.white
        statsView.font = getPungyuFont(size: 13, weight: .medium)
        statsView.stringValue = ""
        statsView.lineBreakMode = .byTruncatingTail
        statsView.identifier = NSUserInterfaceItemIdentifier("statsView")
        statsContainer.addSubview(statsView)

        // 底部區域 - 更新背景顏色
        let bottomArea = NSView()
        bottomArea.translatesAutoresizingMaskIntoConstraints = false
        bottomArea.wantsLayer = true
        bottomArea.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 0.95).cgColor
        contentView.addSubview(bottomArea)

        // 改進動作容器設計 - 優化 Linear App 風格和配色
        let actionContainer = NSView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.wantsLayer = true
        actionContainer.layer?.cornerRadius = 12
        
        // 更新漸變效果和配色，使用更精緻的配色方案
        let actionGradient = CAGradientLayer()
        actionGradient.frame = CGRect(x: 0, y: 0, width: 150, height: 42)
        actionGradient.colors = [
            NSColor(red: 0.25, green: 0.25, blue: 0.35, alpha: 1.0).cgColor, // 深灰藍色
            NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).cgColor  // 深灰色
        ]
        actionGradient.startPoint = CGPoint(x: 0, y: 0)
        actionGradient.endPoint = CGPoint(x: 1, y: 1)
        actionGradient.cornerRadius = 12
        actionContainer.layer?.insertSublayer(actionGradient, at: 0)
        
        // 添加精美的邊框效果
        actionContainer.layer?.borderWidth = 1.0
        actionContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        
        // 添加陰影效果
        actionContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        actionContainer.layer?.shadowOffset = CGSize(width: 0, height: 3)
        actionContainer.layer?.shadowRadius = 8
        actionContainer.layer?.shadowOpacity = 1
        bottomArea.addSubview(actionContainer)

        // 修改 copyButton 的設置，使用更現代的設計
        let copyButton = NSButton(title: "複製文字", target: self, action: #selector(copyText))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = NSButton.BezelStyle.inline
        copyButton.isBordered = false
        copyButton.font = getPungyuFont(size: 14, weight: .semibold)
        copyButton.contentTintColor = NSColor.white
        actionContainer.addSubview(copyButton)

        // 創建一個更美觀的圖標
        let copyIcon = NSImageView()
        copyIcon.translatesAutoresizingMaskIntoConstraints = false
        if let iconImage = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "複製") {
            copyIcon.image = iconImage
            copyIcon.contentTintColor = NSColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0) // 淺色圖標
        }
        actionContainer.addSubview(copyIcon)

        // 創建新的說明標籤，包含選擇性複製和略過紅字的說明
        let infoLabel = NSTextField(labelWithString: "選中文字可直接複製 • 複製時會略過紅字")
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = getPungyuFont(size: 12, weight: .regular)
        infoLabel.textColor = NSColor.lightGray
        infoLabel.alignment = .center
        infoLabel.backgroundColor = .clear
        infoLabel.maximumNumberOfLines = 1
        infoLabel.lineBreakMode = .byTruncatingTail
        bottomArea.addSubview(infoLabel)

        // 設置約束
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.bottomAnchor),

            mainArea.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10), // 減少頂部間距
            mainArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainArea.bottomAnchor.constraint(equalTo: bottomArea.topAnchor),

            textContainer.topAnchor.constraint(equalTo: mainArea.topAnchor),
            textContainer.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor, constant: 20),
            textContainer.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor, constant: -20),
            textContainer.bottomAnchor.constraint(equalTo: statsContainer.topAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: textContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),

            textView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            statsContainer.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor, constant: 20),
            statsContainer.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor, constant: -20),
            statsContainer.bottomAnchor.constraint(equalTo: bottomArea.topAnchor, constant: -10),
            statsContainer.heightAnchor.constraint(equalToConstant: 42),

            statsView.leadingAnchor.constraint(equalTo: statsContainer.leadingAnchor, constant: 15),
            statsView.trailingAnchor.constraint(equalTo: statsContainer.trailingAnchor, constant: -15),
            statsView.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor),

            bottomArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomArea.heightAnchor.constraint(equalToConstant: 50),

            actionContainer.trailingAnchor.constraint(equalTo: bottomArea.trailingAnchor, constant: -20),
            actionContainer.centerYAnchor.constraint(equalTo: bottomArea.centerYAnchor),
            actionContainer.heightAnchor.constraint(equalToConstant: 42),
            actionContainer.widthAnchor.constraint(equalToConstant: 120), // 固定寬度

            copyIcon.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: 15),
            copyIcon.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            copyIcon.widthAnchor.constraint(equalToConstant: 20),
            copyIcon.heightAnchor.constraint(equalToConstant: 20),

            copyButton.leadingAnchor.constraint(equalTo: copyIcon.trailingAnchor, constant: 8),
            copyButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor, constant: -15),

            infoLabel.centerXAnchor.constraint(equalTo: bottomArea.centerXAnchor),
            infoLabel.centerYAnchor.constraint(equalTo: bottomArea.centerYAnchor),
        ])
        
        appDelegate.textWindow?.makeKeyAndOrderFront(nil)
        appDelegate.textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        // 存儲對這些組件的引用
        appDelegate.currentTextView = textView

        // 避免抖動的設置
        scrollView.autohidesScrollers = false // 修改為始終顯示滾動條
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        
        // 設置字體
        textView.font = getPungyuFont(size: 22)
        
        // 設置自動調整大小的通知監聽
        NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            // 使用 Task 包裝以確保在 MainActor 上運行
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
            }
        }
        
        // 添加文本存儲變更通知監聽
        NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage,
            queue: .main
        ) { [weak self] _ in
            // 使用 Task 包裝以確保在 MainActor 上運行
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
            }
        }
        
        // 添加視窗通知監聽，確保頂部框框在視窗大小變更時保持
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: appDelegate.textWindow,
            queue: .main
        ) { [weak self] _ in
            // 使用主線程而非Task，避免捕獲非Sendable類型
            DispatchQueue.main.async {
                guard let strongSelf = self, let window = appDelegate.textWindow else { return }
                
                // 不直接捕獲topBarGradient，而是重新尋找頂部裝飾條視圖
                if let contentView = window.contentView {
                    let allViews = contentView.subviews.flatMap { strongSelf.getAllSubviews(view: $0) }
                    let topBarView = allViews.first { view in 
                        if let gradientLayers = view.layer?.sublayers?.filter({ $0 is CAGradientLayer }) {
                            return !gradientLayers.isEmpty && view.frame.height <= 10 // 頂部裝飾條的特徵
                        }
                        return false
                    }
                    
                    // 如果找到頂部裝飾條，更新其漸變層
                    if let topBarView = topBarView, let gradientLayer = topBarView.layer?.sublayers?.first as? CAGradientLayer {
                        gradientLayer.frame = CGRect(x: 0, y: 0, width: window.frame.width, height: 5)
                        
                        // 強制重繪以確保可見性
                        topBarView.needsDisplay = true
                    }
                }
            }
        }

        // 禁用視窗背景可移動性，讓文字可以被選取
        appDelegate.textWindow?.isMovableByWindowBackground = false
        
        // 確保文字視圖可以接收滑鼠事件，允許文字選取
        textView.isSelectable = true

        // 開始重寫
        appDelegate.rewriteText()

        // 添加鍵盤監聽器
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 8 { // Cmd + C
                self?.copyText()
                return nil
            } else if event.keyCode == 36 { // Enter
                self?.copyText()
                return nil
            }
            return event
        }
    }
    
    // 修改複製文本的方法，修復錯誤並直接略過紅字
    @objc func copyText() {
        guard let appDelegate = appDelegate,
              let textView = appDelegate.currentTextView,
              !textView.string.isEmpty else { return }
        
        var textToCopy: String
        
        // 檢查是否有選中文字 - 修復錯誤
        let selectedRange = textView.selectedRange()
        if selectedRange.length > 0 {
            // 如果有選中文字，則只處理選中部分
            // 直接處理選中的attributedString，移除未使用的selectedText變量
            let selectedAttributedString = textView.attributedString().attributedSubstring(from: selectedRange)
            textToCopy = processAttributedStringForCopy(attributedString: selectedAttributedString)
        } else {
            // 如果沒有選中文字，處理整個文字並略過紅字
            textToCopy = processTextForCopy(textView: textView)
        }
        
        // 將文本複製到剪貼板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)
        
        // 顯示複製成功的圖標和動畫
        if let window = appDelegate.textWindow {
            showCopyFeedback(in: window)
        }
    }
    
    // 修改處理複製文本的方法，默認略過紅字
    private func processTextForCopy(textView: NSTextView) -> String {
        // 處理整個文本的屬性字串，始終略過紅字
        return processAttributedStringForCopy(attributedString: textView.attributedString())
    }
    
    // 新增輔助方法，處理屬性字串並略過紅字
    private func processAttributedStringForCopy(attributedString: NSAttributedString) -> String {
        let mutableResult = NSMutableAttributedString()
        
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { (attrs, range, _) in
            // 檢查是否是刪除線文字（紅字）
            if let strikethroughStyle = attrs[.strikethroughStyle] as? Int, 
               strikethroughStyle == NSUnderlineStyle.single.rawValue,
               let strikethroughColor = attrs[.strikethroughColor] as? NSColor,
               strikethroughColor.isClose(to: NSColor.red) {
                // 這是刪除的文字（紅字），跳過
                return
            }
            
            // 非紅字，添加到結果中
            let substring = attributedString.attributedSubstring(from: range)
            mutableResult.append(substring)
        }
        
        return mutableResult.string
    }
    
    // 顯示複製成功的視覺反饋
    private func showCopyFeedback(in window: NSWindow) {
        // 創建一個圖標視圖
        let iconSize: CGFloat = 80
        let iconView = NSImageView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        
        // 設置圖標
        if let copyImage = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "已複製") {
            iconView.image = copyImage
            iconView.contentTintColor = NSColor.systemBlue
        } else {
            // 如果系統圖標不可用，使用文字
            let textLabel = NSTextField(labelWithString: "已複製")
            textLabel.frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
            textLabel.alignment = .center
            textLabel.font = getPungyuFont(size: 16, weight: .bold)
            textLabel.textColor = NSColor.white
            textLabel.backgroundColor = NSColor.clear
            
            // 將文本標籤添加到窗口中心
            if let contentView = window.contentView {
                textLabel.frame.origin.x = (contentView.frame.width - iconSize) / 2
                textLabel.frame.origin.y = (contentView.frame.height - iconSize) / 2
                contentView.addSubview(textLabel)
                
                // 淡入淡出動畫
                textLabel.alphaValue = 0.0
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    textLabel.alphaValue = 1.0
                }, completionHandler: {
                    // 短暫顯示後淡出
                    Task { @MainActor in
                        // 等待 0.5 秒
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                        
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.3
                            textLabel.alphaValue = 0.0
                        }, completionHandler: {
                            textLabel.removeFromSuperview()
                        })
                    }
                })
            }
            
            return
        }
        
        // 設置圖標視圖的屬性
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor.systemBlue
        
        // 創建一個帶有背景的容器視圖
        let containerSize: CGFloat = 120
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: containerSize, height: containerSize))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.darkGray.withAlphaComponent(0.8).cgColor
        containerView.layer?.cornerRadius = 15
        
        // 將圖標添加到容器中
        iconView.frame.origin.x = (containerSize - iconSize) / 2
        iconView.frame.origin.y = (containerSize - iconSize) / 2
        containerView.addSubview(iconView)
        
        // 將容器添加到窗口中心
        if let contentView = window.contentView {
            containerView.frame.origin.x = (contentView.frame.width - containerSize) / 2
            containerView.frame.origin.y = (contentView.frame.height - containerSize) / 2
            contentView.addSubview(containerView)
            
            // 淡入淡出動畫
            containerView.alphaValue = 0.0
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                containerView.alphaValue = 1.0
                }, completionHandler: {
                // 短暫顯示後淡出
                Task { @MainActor in
                    // 等待 0.5 秒
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                    
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        containerView.alphaValue = 0.0
                    }, completionHandler: {
                        containerView.removeFromSuperview()
                    })
                }
            })
        }
    }

    // 修改函數來更新文本統計資訊 - 美化 Linear App 風格
    private func updateTextStatistics(originalText: String, correctedText: String, statsView: NSTextField) {
        // 計算字元數
        let correctedCharCount = correctedText.count
        
        // 計算變更次數
        let changesCount = calculateChanges(original: originalText, rewritten: correctedText)
        
        // 更新統計資訊顯示，包含模型名稱
        let statsString = "字元數: \(correctedCharCount) • 改變: \(changesCount) • 模型: GPT-4o-mini"
        
        // 創建帶樣式的屬性字串
        let attributedString = NSMutableAttributedString(string: statsString)
        
        // 定義不同部分的範圍
        let charCountRange = (statsString as NSString).range(of: "字元數: \(correctedCharCount)")
        let changesRange = (statsString as NSString).range(of: "改變: \(changesCount)")
        let modelRange = (statsString as NSString).range(of: "模型: GPT-4o-mini")
        
        // 設置基本屬性
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]
        
        // 設置不同部分的顏色 - Linear App 風格
        let charCountAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 13, weight: .semibold),
            .foregroundColor: NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        ]
        
        let changesAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 13, weight: .semibold),
            .foregroundColor: NSColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1.0)
        ]
        
        let modelAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 13, weight: .semibold),
            .foregroundColor: NSColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1.0)
        ]
        
        // 應用基本屬性
        attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: statsString.count))
        
        // 應用各部分特定屬性
        attributedString.addAttributes(charCountAttributes, range: charCountRange)
        attributedString.addAttributes(changesAttributes, range: changesRange)
        attributedString.addAttributes(modelAttributes, range: modelRange)
        
        // 添加點分隔符樣式 (Linear App 常用分隔方式)
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.lightGray.withAlphaComponent(0.7),
            .font: getPungyuFont(size: 15, weight: .bold)
        ]
        
        let separatorRanges = (statsString as NSString).ranges(of: " • ")
        for range in separatorRanges {
            attributedString.addAttributes(separatorAttributes, range: range)
        }
        
        // 更新顯示
        statsView.attributedStringValue = attributedString
    }

    // 添加函數計算文本變化的數量
    private func calculateChanges(original: String, rewritten: String) -> Int {
        // 使用 TextProcessing 獲取差異
        let diff = TextProcessing.diffStrings(original, rewritten)
        var changesCount = 0
        
        // 統計 insert 和 delete 操作的數量
        for change in diff {
            switch change {
            case .insert, .delete:
                changesCount += 1
            case .equal:
                continue
            }
        }
        
        return changesCount
    }
    
    // 修改updateTextViewWithDiff方法，增加處理API完成邏輯
    func updateTextViewWithDiff(originalText: String, newText: String, textView: NSTextView) {
        // 如果API已完成並儲存了完整結果，使用完整結果而非流式顯示
        if let completedResult = completeResult {
            // 使用完整結果進行渲染
            renderFinalComparisonResult(originalText: completedResult.originalText, 
                                       newText: completedResult.newText, 
                                       textView: textView)
            
            // 清理暫存的完整結果
            completeResult = nil
            return
        }
        
        // 判斷文本長度，超過設定大小就分批處理
        let maxTextLength = 5000 // 設定單次處理的最大字符數
        
        // 如果原始文本或重寫文本長度超過最大值，則分段處理
        if originalText.count > maxTextLength || newText.count > maxTextLength {
            // 使用分段處理函數
            processLongTextComparison(originalText: originalText, newText: newText, textView: textView)
            return
        }
        
        // 原有的處理邏輯 (用於短文本)
        let attributedString = NSMutableAttributedString()
        
        // 使用預處理方法處理輸入文本
        let (processedOriginal, processedRewritten) = TextProcessing.preprocessTexts(original: originalText, rewritten: newText)
        
        // 取得差異
        let diff = TextProcessing.diffStrings(processedOriginal, processedRewritten)
        
        // 透過 TextProcessing 的優化方法處理差異
        let optimizedDiff = TextProcessing.optimizeDiff(diff)
        
        // 定義基本樣式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8  // 增加行間距，讓文字更易讀
        paragraphStyle.lineBreakMode = .byWordWrapping // 確保按單詞換行
        paragraphStyle.alignment = .left // 確保左對齊
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 22), // 使用粉圓體
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        // 使用優化後的差異重新生成 attributedString
        for change in optimizedDiff {
            switch change {
            case .equal(let text):
                attributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .insert(let text):
                var attributes = baseAttributes
                attributes[.backgroundColor] = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.3)
                attributes[.foregroundColor] = NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            case .delete(let text):
                var attributes = baseAttributes
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.red
                attributes[.foregroundColor] = NSColor.red.withAlphaComponent(0.8)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        
        updateTextViewWithAttributedString(attributedString: attributedString, originalText: originalText, newText: newText, textView: textView)
    }
    
    // 新增方法，處理API完成標記
    func markAPICompleted(originalText: String, newText: String) {
        isAPICompleted = true
        completeResult = (originalText: originalText, newText: newText)
        
        // 如果AppDelegate中有當前文本視圖，直接觸發更新
        if let appDelegate = appDelegate, let textView = appDelegate.currentTextView {
            Task { @MainActor in
                updateTextViewWithDiff(originalText: originalText, newText: newText, textView: textView)
            }
        }
    }
    
    // 新方法：直接渲染最終比較結果
    private func renderFinalComparisonResult(originalText: String, newText: String, textView: NSTextView) {
        print("直接渲染最終比較結果，跳過流式顯示")
        
        // 創建富文本結果
        let attributedString = NSMutableAttributedString()
        
        // 使用預處理方法處理輸入文本
        let (processedOriginal, processedRewritten) = TextProcessing.preprocessTexts(original: originalText, rewritten: newText)
        
        // 取得差異
        let diff = TextProcessing.diffStrings(processedOriginal, processedRewritten)
        
        // 透過 TextProcessing 的優化方法處理差異
        let optimizedDiff = TextProcessing.optimizeDiff(diff)
        
        // 定義基本樣式，添加明確的段落分隔
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8  // 增加行間距
        paragraphStyle.paragraphSpacing = 12 // 增加段落間距
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .left
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 22),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        // 優化差異識別 - 考慮中文特性
        for change in optimizedDiff {
            switch change {
            case .equal(let text):
                // 對於相等部分，保持原樣
                attributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .insert(let text):
                // 對於插入部分，使用綠色高亮顯示
                var attributes = baseAttributes
                attributes[.backgroundColor] = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.3)
                attributes[.foregroundColor] = NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
                // 添加一些視覺上的分隔
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            case .delete(let text):
                // 對於刪除部分，使用刪除線和紅色
                var attributes = baseAttributes
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.red
                attributes[.foregroundColor] = NSColor.red.withAlphaComponent(0.8)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        
        // 一次性更新UI，避免多次重繪
        Task { @MainActor in
            // 更新文本視圖
            textView.layoutManager?.allowsNonContiguousLayout = false
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(attributedString)
            textView.textStorage?.endEditing()
            
            // 尋找和更新統計視圖
            if let appDelegate = self.appDelegate {
                let allViews = appDelegate.textWindow?.contentView?.subviews.flatMap { getAllSubviews(view: $0) } ?? []
                let foundStatsView = allViews.first(where: { ($0 as? NSTextField)?.identifier?.rawValue == "statsView" }) as? NSTextField
                let foundContainer = foundStatsView?.superview
                
                if let foundStatsView = foundStatsView, let container = foundContainer {
                    self.updateTextStatistics(originalText: originalText, correctedText: newText, statsView: foundStatsView)
                    
                    // 顯示統計信息
                    if container.alphaValue == 0 {
                        container.alphaValue = 1.0
                    }
                }
            }
            
            // 調整視窗大小以適應內容
            if let scrollView = textView.enclosingScrollView {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
                
                // 確保滾動到可見區域
                if textView.string.count > 0 {
                    let range = NSRange(location: 0, length: min(100, textView.string.count))
                    textView.scrollRangeToVisible(range)
                }
            }
        }
    }
    
    // 修改 processLongTextComparison 方法，增強中文段落處理能力
    private func processLongTextComparison(originalText: String, newText: String, textView: NSTextView) {
        print("處理長文本：原文字數 \(originalText.count)，新文本字數 \(newText.count)")
        
        // 檢查是否已經有完整結果
        if let completedResult = completeResult {
            renderFinalComparisonResult(originalText: completedResult.originalText, 
                                       newText: completedResult.newText, 
                                       textView: textView)
            completeResult = nil
            return
        }
        
        // 改進段落分割策略 - 優先考慮中文段落特性
        let originalParagraphs = smartParagraphSplit(text: originalText)
        let newParagraphs = smartParagraphSplit(text: newText)
        
        // 合併段落以達到更好的處理粒度
        let originalChunks = chunkParagraphs(paragraphs: originalParagraphs)
        let newChunks = chunkParagraphs(paragraphs: newParagraphs)
        
        // 創建最終的 attributedString
        let finalAttributedString = NSMutableAttributedString()
        
        // 定義基本樣式 - 增強行間距
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        paragraphStyle.paragraphSpacing = 12 // 增加段落間距
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .left
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: getPungyuFont(size: 22),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        // 處理每組段落的差異
        let chunkCount = max(originalChunks.count, newChunks.count)
        for i in 0..<chunkCount {
            let originalChunk = i < originalChunks.count ? originalChunks[i] : ""
            let newChunk = i < newChunks.count ? newChunks[i] : ""
            
            // 使用預處理方法處理輸入文本
            let (processedOriginal, processedRewritten) = TextProcessing.preprocessTexts(original: originalChunk, rewritten: newChunk)
            
            // 取得差異
            let diff = TextProcessing.diffStrings(processedOriginal, processedRewritten)
            
            // 優化差異
            let optimizedDiff = TextProcessing.optimizeDiff(diff)
            
            // 將差異添加到最終 attributedString
            for change in optimizedDiff {
            switch change {
            case .equal(let text):
                    finalAttributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .insert(let text):
                    var attributes = baseAttributes
                    attributes[.backgroundColor] = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.3)
                    attributes[.foregroundColor] = NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
                    finalAttributedString.append(NSAttributedString(string: text, attributes: attributes))
                case .delete(let text):
                    var attributes = baseAttributes
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.strikethroughColor] = NSColor.red
                    attributes[.foregroundColor] = NSColor.red.withAlphaComponent(0.8)
                    finalAttributedString.append(NSAttributedString(string: text, attributes: attributes))
                }
            }
            
            // 每處理一組段落後，如果不是最後一組，則添加換行符
            if i < chunkCount - 1 {
                finalAttributedString.append(NSAttributedString(string: "\n\n", attributes: baseAttributes)) // 添加兩個換行符增強段落感
            }
        }
        
        // 更新 UI
        updateTextViewWithAttributedString(attributedString: finalAttributedString, originalText: originalText, newText: newText, textView: textView)
    }
    
    // 新增智能段落分割方法 - 考慮中文特性
    private func smartParagraphSplit(text: String) -> [String] {
        // 基本的段落分割（使用換行符）
        var paragraphs = text.components(separatedBy: .newlines)
        
        // 過濾掉空白段落
        paragraphs = paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // 如果段落太少，嘗試按句號、問號、驚嘆號等標點符號分割
        if paragraphs.count <= 1 {
            let sentenceDelimiters = CharacterSet(charactersIn: "。！？.!?")
            var sentences: [String] = []
            
            for paragraph in paragraphs {
                // 先按標點符號分割
                var currentSentence = ""
                
                for (i, char) in paragraph.enumerated() {
                    let currentIndex = paragraph.index(paragraph.startIndex, offsetBy: i)
                    currentSentence.append(char)
                    
                    // 當遇到句末標點且不是段落結尾時，添加到句子列表
                    if sentenceDelimiters.contains(char.unicodeScalars.first!) && currentIndex != paragraph.index(before: paragraph.endIndex) {
                        let nextIndex = paragraph.index(after: currentIndex)
                        
                        // 如果後面還有字符，確認不是連續標點
                        if nextIndex < paragraph.endIndex {
                            let nextChar = paragraph[nextIndex]
                            if !sentenceDelimiters.contains(nextChar.unicodeScalars.first!) {
                                sentences.append(currentSentence)
                                currentSentence = ""
                            }
                        }
                    }
                }
                
                // 添加最後一個句子（如果有）
                if !currentSentence.isEmpty {
                    sentences.append(currentSentence)
                }
            }
            
            // 如果有分割出句子，使用句子代替段落
            if !sentences.isEmpty {
                return sentences
            }
        }
        
        return paragraphs
    }

    // 提取通用的 UI 更新邏輯到一個單獨的方法
    private func updateTextViewWithAttributedString(attributedString: NSAttributedString, originalText: String, newText: String, textView: NSTextView) {
        // 使用 Task 和 @MainActor 替換 DispatchQueue.main.async，並改進批次更新機制
        Task { @MainActor in
            // 暫時禁用視窗調整，避免在更新文本時調整視窗大小
            textView.layoutManager?.allowsNonContiguousLayout = false // 避免非連續布局導致的閃爍
            textView.textStorage?.beginEditing() // 開始批次編輯
            textView.textStorage?.setAttributedString(attributedString)
            textView.textStorage?.endEditing() // 結束批次編輯，觸發單次布局更新
            
            // 更新統計資訊 - 改進此處的查找方式
            if let appDelegate = self.appDelegate {
                // 尋找統計容器視圖
                let mainArea = appDelegate.textWindow?.contentView?.subviews.first(where: { $0.identifier?.rawValue == "mainArea" })
                let statsContainer = mainArea?.subviews.first(where: { $0.wantsLayer && $0.layer?.cornerRadius == 12 })
                
                // 尋找統計文字視圖
                let statsView = statsContainer?.subviews.compactMap { $0 as? NSTextField }
                    .first(where: { $0.identifier?.rawValue == "statsView" })
                
                if let statsView = statsView, let container = statsContainer {
                    // 更新統計信息
                    self.updateTextStatistics(originalText: originalText, correctedText: newText, statsView: statsView)
                    
                    // 比較完成後，添加淡入動畫顯示統計信息
                    if container.alphaValue == 0 {
                        container.alphaValue = 1.0 // 直接設置，避免使用動畫上下文
                    }
                } else {
                    // 嘗試直接在視窗中查找
                    let allViews = appDelegate.textWindow?.contentView?.subviews.flatMap { getAllSubviews(view: $0) } ?? []
                    let foundStatsView = allViews.first(where: { ($0 as? NSTextField)?.identifier?.rawValue == "statsView" }) as? NSTextField
                    let foundContainer = foundStatsView?.superview
                    
                    if let foundStatsView = foundStatsView, let container = foundContainer {
                        self.updateTextStatistics(originalText: originalText, correctedText: newText, statsView: foundStatsView)
                        
                        // 比較完成後，添加淡入動畫顯示統計信息
                        if container.alphaValue == 0 {
                            container.alphaValue = 1.0 // 直接設置，避免使用動畫上下文
                        }
                    } else {
                        print("無法找到 statsView")
                    }
                }
            }
            
            // 等待布局完成
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            // 安全的滾動到文本末尾，確保在主執行緒上執行
            if textView.string.count > 0 {
                let endRange = NSRange(location: max(0, textView.string.count - 1), length: 1)
                textView.scrollRangeToVisible(endRange)
            }
            
            // 等待滾動完成後再調整視窗大小
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            
            // 確保使用 self 而不是 [weak self]，因為 @MainActor 任務已經避免了記憶體循環
                if let scrollView = textView.enclosingScrollView {
                self.updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
                
                // 再次確保內容可見，但直接在這裡執行，而不是調用可能會造成執行緒問題的方法
                if textView.string.count > 0 {
                    let endRange = NSRange(location: max(0, textView.string.count - 1), length: 1)
                    textView.scrollRangeToVisible(endRange)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }
    }
    
    // 重寫方法確保安全性：確保文本視圖滾動到最新內容位置
    @MainActor
    private func ensureVisibleLastContent(in textView: NSTextView) {
        // 計算文本末尾的範圍
        let length = textView.string.count
        if length > 0 {
            let endRange = NSRange(location: max(0, length - 1), length: 1)
            
            // 滾動到文本末尾
            textView.scrollRangeToVisible(endRange)
            
            // 強制更新滾動視圖
            if let scrollView = textView.enclosingScrollView {
                    scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    // 輔助函數，遞歸獲取所有子視圖
    private func getAllSubviews(view: NSView) -> [NSView] {
        var result = [view]
        for subview in view.subviews {
            result.append(contentsOf: getAllSubviews(view: subview))
        }
        return result
    }

    // 添加一個方法以在需要時調整窗口大小
    private func updateWindowSizeIfNeeded(textView: NSTextView, scrollView: NSScrollView) {
        guard let appDelegate = appDelegate, let window = appDelegate.textWindow else { return }
        
        // 使用類別級別的靜態屬性
        let currentTime = Date().timeIntervalSince1970
        
        // 如果距離上次調整不到 0.2 秒，則忽略此次調整
        if currentTime - TextWindowManager.lastResizeTime < 0.2 {
            return
        }
        
        // 計算實際需要的內容高度（更準確的方法）
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!
        
        // 獲取整個文本內容所需的矩形
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        
        // 添加文本容器插入的空間
        boundingRect.size.height += textView.textContainerInset.height * 2
        
        // 額外添加兩行的高度，確保框框始終比文字多一兩行
        let lineHeight = getPungyuFont(size: 22).boundingRectForFont.height // 根據使用粉圓體的字體大小計算行高
        boundingRect.size.height += lineHeight * 2.5 // 額外添加 2.5 行高度
        
        // 計算視窗需要的最小高度 (考慮其他UI元素)
        let minRequiredHeight = boundingRect.height + 150 // 底部和頂部的空間
        
        // 獲取螢幕可見區域
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
        let maxHeight = screenHeight * 0.8 // 最大高度為螢幕高度的80%
        
        // 計算新的窗口高度，並四捨五入到最接近的整數，以減少微小調整
        let newHeight = min(max(round(minRequiredHeight), 300), maxHeight) // 確保在最小和最大範圍內
        
        // 如果需要調整大小
        let currentSize = window.frame.size
        let heightDifference = abs(currentSize.height - newHeight)
        
        // 只有當高度差距超過閾值時才調整，增加閾值減少抖動
        if heightDifference > 80 { 
            // 更新最後調整時間
            TextWindowManager.lastResizeTime = currentTime
            
            // 保持寬度不變，只調整高度
            let newSize = NSSize(width: currentSize.width, height: newHeight)
            
            // 保持窗口頂部位置不變（與中心不同），這樣底部會自然展開或收縮
            let newOrigin = NSPoint(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - newHeight // 保持頂部位置固定
            )
            
            // 設置新的框架
            let newFrame = NSRect(origin: newOrigin, size: newSize)
            
            // 動畫平滑過渡到新的尺寸，增加持續時間使過渡更平滑
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4 // 延長動畫時間
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) // 使用平滑的加速減速
                context.allowsImplicitAnimation = true
                window.setFrame(newFrame, display: true, animate: true)
                
                // 在動畫期間確保頂部框框可見
                if let contentView = window.contentView {
                    let allViews = contentView.subviews.flatMap { getAllSubviews(view: $0) }
                    let topBarView = allViews.first { $0.layer?.sublayers?.first is CAGradientLayer }
                    topBarView?.layer?.opacity = 1.0 // 確保頂部框框可見
                }
            }
            
            // 確保文本視圖滾動到可見區域
            Task { @MainActor in
                // 等待動畫完成
                try? await Task.sleep(nanoseconds: 450_000_000) // 0.45秒
                
                let range = NSRange(location: textView.string.count, length: 0)
                textView.scrollRangeToVisible(range)
                
                // 重新檢查頂部框框是否可見
                if let contentView = window.contentView {
                    let allViews = contentView.subviews.flatMap { getAllSubviews(view: $0) }
                    let topBarView = allViews.first { $0.layer?.sublayers?.first is CAGradientLayer }
                    topBarView?.layer?.opacity = 1.0 // 確保頂部框框可見
                }
            }
        } else if heightDifference > 0 {
            // 即使不做尺寸調整，也確保滾動到可見區域
            let range = NSRange(location: textView.string.count, length: 0)
            textView.scrollRangeToVisible(range)
        }
    }
    
    // 更新窗口大小的方法 - 可以從外部調用
    func resizeWindowToFitContent() {
        guard let appDelegate = appDelegate,
              let textView = appDelegate.currentTextView,
              let scrollView = textView.enclosingScrollView else { return }
        
        updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
    }

    // 輔助函數：將段落分成多個塊來處理
    private func chunkParagraphs(paragraphs: [String]) -> [String] {
        let maxParagraphsPerChunk = 5 // 每塊最多包含的段落數
        let maxChunkLength = 1000     // 每塊最大字符數
        
        var chunks = [String]()
        var currentChunk = ""
        var paragraphCount = 0
        
        for paragraph in paragraphs {
            // 如果當前塊已經達到最大段落數或加上新段落會超過最大長度，則開始新塊
            if paragraphCount >= maxParagraphsPerChunk || (currentChunk + paragraph).count > maxChunkLength {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }
                currentChunk = paragraph
                paragraphCount = 1
            } else {
                // 否則，將段落添加到當前塊
                if !currentChunk.isEmpty {
                    currentChunk += "\n"
                }
                currentChunk += paragraph
                paragraphCount += 1
            }
        }
        
        // 添加最後一個塊（如果有）
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
}

// 添加 NSString 擴展來查找所有匹配的範圍
private extension NSString {
    func ranges(of string: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: self.length)
        
        while true {
            let range = self.range(of: string, options: [], range: searchRange)
            if range.location == NSNotFound {
                break
            }
            
            ranges.append(range)
            searchRange.location = range.location + range.length
            searchRange.length = self.length - searchRange.location
        }
        
        return ranges
    }
}

// 添加顏色比較擴展
extension NSColor {
    func isClose(to color: NSColor, tolerance: CGFloat = 0.2) -> Bool {
        guard let convertedSelf = self.usingColorSpace(.genericRGB),
              let convertedColor = color.usingColorSpace(.genericRGB) else {
            return false
        }
        
        let redDiff = abs(convertedSelf.redComponent - convertedColor.redComponent)
        let greenDiff = abs(convertedSelf.greenComponent - convertedColor.greenComponent)
        let blueDiff = abs(convertedSelf.blueComponent - convertedColor.blueComponent)
        
        return redDiff < tolerance && greenDiff < tolerance && blueDiff < tolerance
    }
}

// 添加 String.substring 擴展用於處理 NSRange 轉換
extension String {
    func substring(with range: Range<String.Index>?) -> String? {
        if let range = range {
            return String(self[range])
        }
        return nil
    }
}