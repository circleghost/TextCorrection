import Cocoa
import os.log

// 將整個類標記為 @MainActor，因為它主要處理 UI 元素
@MainActor
class TextWindowManager: ObservableObject {
    weak var appDelegate: AppDelegate?
    
    // 將靜態屬性移到類別級別
    private static var lastResizeTime: TimeInterval = 0
    
    // 添加控制窗口調整的屬性
    private var shouldAdjustWindow = true
    
    // 在類中添加新的屬性用於跟踪API完成狀態
    private var isAPICompleted = false
    private var completeResult: (originalText: String, newText: String)? = nil
    
    // 添加頂部裝飾相關屬性
    private var topBarView: NSView?
    private var controlsContainerView: NSView?
    private var topContainer: NSView? // 添加topContainer引用
    
    // 添加統計視圖相關屬性
    private var statsView: NSTextField?
    private var statsContainer: NSView?
    
    // 添加通知觀察者的存儲，以便正確移除
    private var observers: [NSObjectProtocol] = []
    
    // 添加鍵盤監聽器引用屬性
    private var keyboardMonitor: Any?
    
    // 添加固定頂部視圖的定時器
    private var topBarFixTimer: Timer?
    
    // 添加粉圓體字體輔助方法
    private func getPungyuFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.pungyu(size: size, weight: weight)
    }
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        // 檢查權限
        _ = checkAppleEventsPermission()
    }
    
    // 新增一個用於檢查和請求權限的輔助方法
    private func checkAppleEventsPermission() -> Bool {
        let scriptString = """
        tell application "System Events"
            return true
        end tell
        """
        
        let appleScript = NSAppleScript(source: scriptString)
        var errorInfo: NSDictionary?
        let scriptResult = appleScript?.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            // 記錄錯誤但不崩潰
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .error("未獲得Apple Events權限: \(error)")
            
            // 如果是權限錯誤，顯示提示給用戶
            if let errorNumber = error[NSAppleScript.errorNumber] as? NSNumber,
               errorNumber.intValue == -1743 {
                // 在主線程顯示權限提示
                DispatchQueue.main.async {
                    self.showPermissionAlert()
                }
            }
            return false
        }
        
        return scriptResult != nil
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要系統事件權限"
        alert.informativeText = """
        此應用需要「系統事件」權限才能正常運作。這個權限用於：
        • 讀取選中的文字
        • 監控剪貼板變化
        • 與系統進行必要的互動
        
        請前往「系統設定 > 隱私權與安全性 > 自動化」並允許應用存取「系統事件」。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "開啟系統設定")
        alert.addButton(withTitle: "稍後再說")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // 開啟系統設定的隱私與安全性頁面
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
    
    func showTextWindow(text: String) {
        guard let appDelegate = appDelegate else { return }
        
        // 檢查Apple Events權限
        if !checkAppleEventsPermission() {
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").warning("缺少Apple Events權限，但仍繼續嘗試顯示窗口")
        }
        
        // 先關閉現有的文本視窗，避免重複
        if appDelegate.textWindow != nil {
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[顯示窗口] 關閉現有窗口，準備重新創建")
            
            // 在關閉窗口前停止定時器
            topBarFixTimer?.invalidate()
            topBarFixTimer = nil
            
            appDelegate.textWindow?.close()
            appDelegate.textWindow = nil
            
            // 給系統一點時間處理窗口關閉
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[顯示窗口] 延遲後創建新窗口")
                self.createTextWindow(with: text)
            }
            return
        }
        
        // 如果沒有現有視窗，直接創建
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[顯示窗口] 直接創建新窗口")
        createTextWindow(with: text)
    }
    
    // 將原本的 showTextWindow 邏輯分離到一個新方法
    private func createTextWindow(with text: String) {
        guard let appDelegate = appDelegate else { 
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .error("無法創建文本窗口：appDelegate為nil")
            return 
        }
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[創建窗口] 開始創建文本窗口")
        
        // 確保 AppState 有原始文本
        AppState.shared.originalText = text
        
        // 同時設置 AppDelegate 的原始文本屬性
        appDelegate.originalText = text
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        // 設定視窗大小為螢幕的 60% 寬度和 40% 高度，增加初始高度
        let width = screenFrame.width * 0.6
        let height = screenFrame.height * 0.4
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

        // 添加漸變背景 - 修改為插入到最底層
        let gradient = CAGradientLayer()
        gradient.frame = (appDelegate.textWindow?.contentView?.bounds)!
        gradient.colors = [NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.9).cgColor,
                           NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.9).cgColor]
        gradient.locations = [0.0, 1.0]
        appDelegate.textWindow?.contentView?.layer?.insertSublayer(gradient, at: 0)

        appDelegate.textWindow?.isOpaque = false
        appDelegate.textWindow?.backgroundColor = .clear
        appDelegate.textWindow?.hasShadow = true
        appDelegate.textWindow?.appearance = NSAppearance(named: .darkAqua)
        
        appDelegate.textWindow?.minSize = NSSize(width: 400, height: 250)
        
        // 現代化視窗設計 - 移除標題，添加頂部裝飾條
        appDelegate.textWindow?.titleVisibility = .hidden
        appDelegate.textWindow?.titlebarAppearsTransparent = true
        
        // 創建一個容器視圖，用於固定在視窗頂部的元素
        let topContainer = NSView()
        topContainer.translatesAutoresizingMaskIntoConstraints = false
        topContainer.wantsLayer = true
        // 設置深色背景，確保整個頂部條帶都是不透明的
        topContainer.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
        appDelegate.textWindow?.contentView?.addSubview(topContainer)
        self.topContainer = topContainer
        
        // 確保topContainer固定在視窗頂部
        NSLayoutConstraint.activate([
            topContainer.topAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.topAnchor),
            topContainer.leadingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.leadingAnchor),
            topContainer.trailingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.trailingAnchor),
            topContainer.heightAnchor.constraint(equalToConstant: 33) // 足夠容納控制按鈕和裝飾條
        ])
        
        // 添加視窗控制按鈕容器，確保控制按鈕在正確位置
        let controlsContainerView = NSView()
        controlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainerView.wantsLayer = true
        // 設置背景色，確保按鈕容器不透明
        controlsContainerView.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
        topContainer.addSubview(controlsContainerView)
        self.controlsContainerView = controlsContainerView
        
        NSLayoutConstraint.activate([
            controlsContainerView.topAnchor.constraint(equalTo: topContainer.topAnchor),
            controlsContainerView.leadingAnchor.constraint(equalTo: topContainer.leadingAnchor),
            controlsContainerView.heightAnchor.constraint(equalToConstant: 28),
            controlsContainerView.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        // 獲取系統標準按鈕並添加到控制容器
        if let closeButton = appDelegate.textWindow?.standardWindowButton(.closeButton),
           let miniaturizeButton = appDelegate.textWindow?.standardWindowButton(.miniaturizeButton),
           let zoomButton = appDelegate.textWindow?.standardWindowButton(.zoomButton) {
           
            // 將按鈕從原位置移除並添加到控制容器
            closeButton.removeFromSuperview()
            miniaturizeButton.removeFromSuperview()
            zoomButton.removeFromSuperview()
            
            controlsContainerView.addSubview(closeButton)
            controlsContainerView.addSubview(miniaturizeButton)
            controlsContainerView.addSubview(zoomButton)
            
            // 設置按鈕位置
            closeButton.frame.origin = CGPoint(x: 8, y: 8)
            miniaturizeButton.frame.origin = CGPoint(x: 28, y: 8)
            zoomButton.frame.origin = CGPoint(x: 48, y: 8)
        }
        
        // 創建頂部裝飾條，添加到topContainer而不是直接加到contentView
        let topBarView = NSView()
        topBarView.wantsLayer = true
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        topContainer.addSubview(topBarView)
        self.topBarView = topBarView
        
        // 使用三色條紋裝飾效果，而非單一顏色
        let topBarLayer = CALayer()
        topBarLayer.frame = CGRect(x: 0, y: 0, width: appDelegate.textWindow!.frame.width, height: 5)
        topBarView.layer?.addSublayer(topBarLayer)
        
        // 創建三個顏色條紋
        let redLayer = CALayer()
        redLayer.backgroundColor = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9).cgColor
        redLayer.frame = CGRect(x: 0, y: 0, width: topBarLayer.frame.width/3, height: 5)
        
        let yellowLayer = CALayer()
        yellowLayer.backgroundColor = NSColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 0.9).cgColor
        yellowLayer.frame = CGRect(x: topBarLayer.frame.width/3, y: 0, width: topBarLayer.frame.width/3, height: 5)
        
        let greenLayer = CALayer()
        greenLayer.backgroundColor = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 0.9).cgColor
        greenLayer.frame = CGRect(x: 2*topBarLayer.frame.width/3, y: 0, width: topBarLayer.frame.width/3, height: 5)
        
        topBarLayer.addSublayer(redLayer)
        topBarLayer.addSublayer(yellowLayer)
        topBarLayer.addSublayer(greenLayer)
        
        // 設置topBarView的約束，確保它位於controlsContainerView下方
        NSLayoutConstraint.activate([
            topBarView.bottomAnchor.constraint(equalTo: topContainer.bottomAnchor),
            topBarView.leadingAnchor.constraint(equalTo: topContainer.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: topContainer.trailingAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 5)  // 薄的裝飾條
        ])
        
        // 移除topBarGradient引用和代碼
        
        // 創建內容視圖，確保它位於topContainer下方
        let contentView = NSView(frame: (appDelegate.textWindow?.contentView?.bounds)!)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        appDelegate.textWindow?.contentView?.addSubview(contentView)
        
        // 修改contentView的約束，使其位於topContainer下方
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topContainer.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.bottomAnchor)
        ])

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

        // 修改scrollView的設置，確保捲動功能正確工作
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true // 確保scrollView可以正確渲染
        scrollView.layer?.zPosition = 100 // 提高z位置確保可見
        textContainer.addSubview(scrollView)

        // 確保scrollView填滿textContainer
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: textContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor)
        ])

        // 修改 textView 的設置
        let textView = NSTextView(frame: scrollView.bounds)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true // 確保用戶可以選擇文本
        textView.allowsUndo = true // 允許撤銷操作
        textView.isFieldEditor = false // 不是字段編輯器
        textView.allowsDocumentBackgroundColorChange = false // 不允許背景顏色改變
        textView.textContainerInset = NSSize(width: 15, height: 15)
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.white
        textView.alignment = .left
        textView.isRichText = true // 允許富文本

        // 啟用捲動必要設置 - 加強
        textView.isVerticallyResizable = true // 確保垂直可調整大小
        textView.isHorizontallyResizable = false // 禁用水平調整，強制換行
        textView.textContainer?.widthTracksTextView = true // 寬度跟隨視圖
        textView.textContainer?.containerSize = NSSize(
            width: 0, // 寬度0表示自動跟隨
            height: CGFloat.greatestFiniteMagnitude // 允許無限高度
        )

        // 統一使用粉圓體字體
        textView.textContainer?.lineFragmentPadding = 5.0
        textView.font = getPungyuFont(size: 26) // 增大字體以便閱讀

        // 設置捲動視圖 - 加強捲動功能
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true // 確保有垂直捲動條
        scrollView.hasHorizontalScroller = false // 禁用水平捲動，強制換行
        scrollView.autohidesScrollers = false // 始終顯示捲動條
        scrollView.scrollerStyle = .overlay // 現代化捲動條
        scrollView.verticalScrollElasticity = .allowed // 允許彈性捲動
        scrollView.horizontalScrollElasticity = .none // 禁止水平彈性捲動
        scrollView.contentView.postsBoundsChangedNotifications = true // 發送範圍通知
        scrollView.borderType = .noBorder // 無邊框
        scrollView.drawsBackground = false
        scrollView.backgroundColor = NSColor.clear // 確保背景透明

        // 提高捲動效能
        scrollView.usesPredominantAxisScrolling = false // 允許同時水平和垂直捲動
        scrollView.scrollsDynamically = true // 啟用動態捲動

        // 捲動條樣式設置
        if let verticalScroller = scrollView.verticalScroller {
            verticalScroller.controlSize = .regular
            verticalScroller.knobStyle = .light // 亮色捲動條
            verticalScroller.knobProportion = 0.2 // 設置捲動條比例，確保可見
        }

        // 初始內容尺寸設置 - 確保滾動區域足夠大
        let extraHeight = getPungyuFont(size: 26).boundingRectForFont.height * 3 // 添加額外空間
        let initialContentSize = NSSize(
            width: scrollView.bounds.width,
            height: max(scrollView.bounds.height, 
                       extraHeight + textView.textContainerInset.height * 2)
        )
        textView.frame.size = initialContentSize

        // 確保scrollView可以正確處理內容尺寸變化
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.autoresizesSubviews = true

        // 添加自定義通知處理 - 確保文字變更時更新捲動區域
        let scrollViewObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak textView, weak scrollView] _ in
            guard let textView = textView, let scrollView = scrollView else { return }
            
            // 確保文字視圖尺寸正確反映內容
            DispatchQueue.main.async {
                // 強制布局以更新尺寸
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                
                // 確保捲動視圖顯示最新內容
                scrollView.reflectScrolledClipView(scrollView.contentView)
                
                // 確保內容可見
                if textView.string.count > 0 {
                    let visibleRect = scrollView.contentView.bounds
                    scrollView.contentView.scrollToVisible(visibleRect)
                }
            }
        }
        observers.append(scrollViewObserver)
        
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
        self.statsContainer = statsContainer

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
        self.statsView = statsView
        
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
        
        // 更新配色方案，使用更精緻的配色
        actionContainer.layer?.backgroundColor = NSColor(red: 0.22, green: 0.22, blue: 0.28, alpha: 1.0).cgColor
        
        // 添加精美的邊框效果
        actionContainer.layer?.borderWidth = 1.0
        actionContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        
        // 添加陰影效果
        actionContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        actionContainer.layer?.shadowOffset = CGSize(width: 0, height: 3)
        actionContainer.layer?.shadowRadius = 8
        actionContainer.layer?.shadowOpacity = 1
        bottomArea.addSubview(actionContainer)

        // 修改 copyButton 的設置，使用更現代的設計
        let copyButton = NSButton(title: "複製全文", target: self, action: #selector(copyText))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = NSButton.BezelStyle.inline
        copyButton.isBordered = false
        copyButton.font = getPungyuFont(size: 14, weight: .semibold)
        copyButton.contentTintColor = NSColor.white
        actionContainer.addSubview(copyButton)

        // 創建一個更美觀的圖標
        let copyIcon = NSImageView()
        copyIcon.translatesAutoresizingMaskIntoConstraints = false
        if let iconImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "複製") {
            copyIcon.image = iconImage
            copyIcon.contentTintColor = NSColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0) // 淺色圖標
        }
        actionContainer.addSubview(copyIcon)

        // 創建新的說明標籤，使用粉圓體且分隔線更明顯
        let infoLabel = NSTextField(labelWithString: "選中文字可單獨複製 · 自動略過紅色錯字")
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
        
        // 存儲對這些組件的引用
        appDelegate.currentTextView = textView

        // 避免抖動的設置
        scrollView.autohidesScrollers = false // 修改為始終顯示滾動條
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        
        // 設置字體
        textView.font = getPungyuFont(size: 26) // 增大字體
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[創建窗口] 窗口和文本視圖已創建並配置完成")
        
        // 確保窗口和文本視圖可見且可互動
        appDelegate.textWindow?.makeKeyAndOrderFront(nil)
        appDelegate.textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[創建窗口] 窗口已設置為前台活躍窗口")
        
        // 更新AppState以反映窗口狀態
        AppState.shared.isTextWindowOpen = true
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[創建窗口] AppState.isTextWindowOpen已設為true")
        
        // 通知窗口狀態變化
        AppKitBridge.shared.notifyWindowStateChanged(type: "text", isVisible: true)
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("[創建窗口] 已發送窗口狀態變更通知")
        
        // 禁用視窗背景可移動性，讓文字可以被選取
        appDelegate.textWindow?.isMovableByWindowBackground = false

        // 確保文字視圖可以接收滑鼠事件，允許文字選取
        textView.isSelectable = true

        // 先顯示處理中狀態，不要立即顯示原始文字
        let processingText = "⏳ 正在進行文字校正，請稍候..."
        let processingString = NSMutableAttributedString(string: processingText)
        processingString.addAttributes([
            .font: getPungyuFont(size: 24),
            .foregroundColor: NSColor.systemYellow
        ], range: NSRange(location: 0, length: processingText.count))
        
        textView.textStorage?.setAttributedString(processingString)
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
            .info("[創建窗口] 已顯示處理中狀態")

        // 開始重寫
        appDelegate.rewriteText()

        // 設置自動調整大小的通知監聽
        let textChangeObserver = NotificationCenter.default.addObserver(
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
        observers.append(textChangeObserver)

        // 添加文本存儲變更通知監聽
        let textStorageObserver = NotificationCenter.default.addObserver(
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
        observers.append(textStorageObserver)

        // 添加視窗通知監聽，確保頂部框框在視窗大小變更時保持
        let windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: appDelegate.textWindow,
            queue: .main
        ) { [weak self] _ in
            // 使用主線程而非Task，避免捕獲非Sendable類型
            DispatchQueue.main.async {
                // 添加強大的錯誤捕獲機制
                do {
                    guard let strongSelf = self, let window = appDelegate.textWindow else { return }
                    
                    // 避免對未初始化或無效的視圖進行操作
                    if window.contentView == nil {
                        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                            .error("視窗的contentView為nil，跳過視圖更新")
                        return
                    }
                    
                    // 安全地訪問視圖 - 使用更嚴格的檢查
                    if let topBarView = strongSelf.topBarView, 
                       topBarView.superview != nil,
                       !topBarView.isHidden {  // 只處理可見的視圖
                        
                        // 確保視圖本身是可見的
                        topBarView.alphaValue = 1.0
                        
                        // 安全地更新三色條紋的寬度
                        try strongSelf.safeUpdateTopColorBar()  // 移除 ? 操作符，讓錯誤能夠被拋出和捕獲
                    }
                    
                    // 確保控制按鈕容器也保持可見和不透明
                    if let controlsContainer = strongSelf.controlsContainerView, 
                       controlsContainer.superview != nil {
                        controlsContainer.isHidden = false
                        controlsContainer.alphaValue = 1.0
                        
                        // 安全地設置背景顏色
                        if controlsContainer.wantsLayer {
                            controlsContainer.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
                        }
                    }
                    
                    // 確保整個頂部容器也保持不透明並維持背景顏色
                    if let topContainer = strongSelf.topContainer, 
                       topContainer.superview != nil {
                        topContainer.isHidden = false
                        topContainer.alphaValue = 1.0
                        
                        // 安全地設置背景顏色
                        if topContainer.wantsLayer {
                            topContainer.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
                        }
                    }
                } catch {
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .error("視窗調整大小監聽器中發生錯誤: \(error.localizedDescription)")
                }
            }
        }
        observers.append(windowResizeObserver)

        // 添加鍵盤監聽器，存儲引用以便後續移除
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 8 { // Cmd + C
                self?.copyText()
                return nil
            } else if event.keyCode == 36 { // Enter
                self?.copyText()
                return nil
            }
            return event
        }
        
        // 設置一個定時器，定期確保頂部裝飾條可見，但降低頻率
        topBarFixTimer?.invalidate() // 先停止已存在的定時器
        topBarFixTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // 使用weak self避免強引用循環
            guard let self = self else {
                return
            }
            
            // 確保在主線程上執行UI更新
            if !Thread.isMainThread {
                DispatchQueue.main.async {
                    Task { @MainActor in
                        self.updateTopBarVisibilityAsync()
                    }
                }
                return
            }
            
            Task { @MainActor in
                self.updateTopBarVisibilityAsync()
            }
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
        // 確保在主線程上執行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateTextViewWithDiff(originalText: originalText, newText: newText, textView: textView)
            }
            return
        }
        
        // 安全檢查
        guard let _ = textView.window else {
            print("錯誤: textView的window為nil，無法更新")
            return
        }
        
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
        paragraphStyle.lineSpacing = 12  // 增加行間距，讓文字更易讀
        paragraphStyle.paragraphSpacing = 16 // 增加段落間距
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
    
    // 修改markAPICompleted方法，改善線程安全性
    func markAPICompleted(originalText: String, newText: String) {
        // 在主線程上設置完成狀態和結果
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.markAPICompleted(originalText: originalText, newText: newText)
            }
            return
        }
        
        // 設置完成狀態和結果
        isAPICompleted = true
        completeResult = (originalText: originalText, newText: newText)
        
        // 如果AppDelegate中有當前文本視圖，直接觸發更新
        if let appDelegate = appDelegate, let textView = appDelegate.currentTextView {
            // 使用弱引用避免強引用循環
            Task { @MainActor [weak self, weak textView, weak appDelegate] in
                // 安全檢查，確保所有引用都還有效
                guard let self = self, 
                      let textView = textView,
                      let _ = appDelegate,
                      let _ = textView.window else {
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .error("完成API處理時，發現無效的視圖引用")
                    return
                }
                
                // 使用優化後的方法更新文本視圖
                self.updateTextViewWithDiff(originalText: originalText, newText: newText, textView: textView)
            }
        } else {
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .warning("API處理完成，但無法找到有效的文本視圖進行更新")
        }
    }
    
    // 新方法：直接渲染最終比較結果
    private func renderFinalComparisonResult(originalText: String, newText: String, textView: NSTextView) {
        // 確保在主線程上執行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.renderFinalComparisonResult(originalText: originalText, newText: newText, textView: textView)
            }
            return
        }
        
        // 安全檢查
        guard let _ = textView.window else {
            print("錯誤: renderFinalComparisonResult中textView的window為nil")
            return
        }
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager").info("直接渲染最終比較結果，跳過流式顯示")
        
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
        paragraphStyle.lineSpacing = 12  // 增加行間距
        paragraphStyle.paragraphSpacing = 16 // 增加段落間距
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
            
            // 直接使用保存的統計視圖引用
            if let statsView = self.statsView, let container = self.statsContainer {
                self.updateTextStatistics(originalText: originalText, correctedText: newText, statsView: statsView)
                
                // 顯示統計信息
                if container.alphaValue == 0 {
                    container.alphaValue = 1.0 // 直接設置，避免使用動畫上下文
                }
            }
            
            // 調整視窗大小以適應內容
            if let scrollView = textView.enclosingScrollView {
                // 確保布局更新
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                
                // 等待布局完成
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                
                // 調整視窗大小
                updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
                
                // 確保捲動到內容頂部，以便用戶可以從頭開始閱讀
                if textView.string.count > 0 {
                    // 首先確保文本視圖有足夠大小容納內容
                    let layoutManager = textView.layoutManager!
                    let textContainer = textView.textContainer!
                    let glyphRange = layoutManager.glyphRange(for: textContainer)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    // 設置文本視圖大小以適應內容
                    let newHeight = boundingRect.height + textView.textContainerInset.height * 2
                    if textView.frame.size.height < newHeight {
                        textView.frame.size.height = newHeight
                    }
                    
                    // 捲動到頂部
                    let topRange = NSRange(location: 0, length: min(100, textView.string.count))
                    textView.scrollRangeToVisible(topRange)
                    
                    // 強制更新捲動視圖
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    
                    // 確保垂直捲動條可見
                    scrollView.hasVerticalScroller = true
                    if let scroller = scrollView.verticalScroller {
                        scroller.isHidden = false
                        scroller.needsDisplay = true
                    }
                    
                    // 記錄捲動操作
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .debug("捲動到內容頂部，確保UI元素可見")
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
        paragraphs = paragraphs.filter { item in
            return !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
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
        // 確保在主線程執行UI更新
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateTextViewWithAttributedString(attributedString: attributedString, 
                                                       originalText: originalText, 
                                                       newText: newText, 
                                                       textView: textView)
            }
            return
        }
        
        // 使用弱引用，避免強引用循環
        Task { @MainActor [weak self, weak textView] in
            // 安全檢查，確保視圖和窗口仍然有效
            guard let self = self,
                  let textView = textView,
                  let window = textView.window,
                  let scrollView = textView.enclosingScrollView else {
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .error("UI 更新時找不到有效的視圖階層")
                return
            }
            
            // 保存目前的滾動位置
            let visibleRect = scrollView.contentView.bounds
            let wasAtBottom = (visibleRect.maxY >= scrollView.documentView?.bounds.maxY ?? 0)
            
            // 使用真正的字符級文字流動效果
            await self.animateTextStream(attributedString: attributedString, textView: textView, window: window)
            
            // 恢復滾動位置
            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            } else {
                scrollView.contentView.scroll(to: visibleRect.origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            
            // 確保文本視圖可見並且窗口更新
            textView.needsDisplay = true
            window.update()
            
            // 更新統計信息
            updateStatisticsInfo(originalText: originalText, correctedText: newText)
            
            // 等待布局完成
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            // 調整視窗大小
            if let scrollView = textView.enclosingScrollView {
                updateWindowSizeIfNeeded(textView: textView, scrollView: scrollView)
            }
            
            // 確保捲動到內容頂部，以便用戶可以從頭開始閱讀
            if textView.string.count > 0 {
                // 首先確保文本視圖有足夠大小容納內容
                let layoutManager = textView.layoutManager!
                let textContainer = textView.textContainer!
                let glyphRange = layoutManager.glyphRange(for: textContainer)
                let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                
                // 設置文本視圖大小以適應內容
                let newHeight = boundingRect.height + textView.textContainerInset.height * 2
                if textView.frame.size.height < newHeight {
                    textView.frame.size.height = newHeight
                }
                
                // 捲動到頂部
                let topRange = NSRange(location: 0, length: min(100, textView.string.count))
                textView.scrollRangeToVisible(topRange)
                
                // 強制更新捲動視圖
                if let scrollView = textView.enclosingScrollView {
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    
                    // 確保垂直捲動條可見
                    scrollView.hasVerticalScroller = true
                    if let scroller = scrollView.verticalScroller {
                        scroller.isHidden = false
                        scroller.needsDisplay = true
                    }
                    
                    // 記錄捲動操作
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .debug("捲動到內容頂部，確保UI元素可見")
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
        var result = [NSView]()
        
        // 使用廣度優先搜索而不是深度優先，通常更高效
        var queue = [view]
        var index = 0
        
        while index < queue.count {
            let currentView = queue[index]
            result.append(currentView)
            
            // 將所有子視圖添加到隊列
            for subview in currentView.subviews {
                queue.append(subview)
            }
            
            index += 1
        }
        
        return result
    }
    
    // 添加一個更高效的方法，可以根據條件尋找特定類型的視圖
    private func findSubview<T: NSView>(ofType type: T.Type, in view: NSView, where condition: ((T) -> Bool)? = nil) -> T? {
        // 首先檢查當前視圖
        if let castedView = view as? T, condition?(castedView) ?? true {
            return castedView
        }
        
        // 遍歷直接子視圖
        for subview in view.subviews {
            if let castedView = subview as? T, condition?(castedView) ?? true {
                return castedView
            }
            
            // 遞歸搜索
            if let foundView = findSubview(ofType: type, in: subview, where: condition) {
                return foundView
            }
        }
        
        return nil
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
            var newOrigin = NSPoint(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - newHeight // 保持頂部位置固定
            )
            
            // 檢查螢幕邊界，確保視窗不會超出螢幕上方
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let maxY = screenFrame.maxY - 20 // 保留一些頂部空間
            
            // 如果新位置會使視窗頂部超出螢幕
            if newOrigin.y + newHeight > maxY {
                newOrigin.y = maxY - newHeight
                
                // 記錄調整，以便調試
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .debug("視窗高度調整：保持在螢幕範圍內")
            }
            
            // 確保視窗不會超出螢幕下方
            if newOrigin.y < screenFrame.minY {
                newOrigin.y = screenFrame.minY
                
                // 記錄調整，以便調試
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .debug("視窗高度調整：避免超出螢幕底部")
            }
            
            // 設置新的框架
            let newFrame = NSRect(origin: newOrigin, size: newSize)
            
            // 在調整前確保頂部裝飾條可見
            if let topBarView = self.topBarView {
                topBarView.isHidden = false
                topBarView.alphaValue = 1.0
            }
            
            // 動畫平滑過渡到新的尺寸，增加持續時間使過渡更平滑
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4 // 延長動畫時間
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) // 使用平滑的加速減速
                context.allowsImplicitAnimation = true
                window.setFrame(newFrame, display: true, animate: true)
                
                // 在動畫期間確保頂部框框可見
                if let topBarView = self.topBarView {
                    topBarView.layer?.opacity = 1.0 // 確保頂部框框可見
                }
            }
            
            // 確保文本視圖滾動到可見區域
            Task { @MainActor in
                // 等待動畫完成
                try? await Task.sleep(nanoseconds: 450_000_000) // 0.45秒
                
                // 捲動到內容頂部，確保用戶能看到完整內容
                if textView.string.count > 0 {
                    let range = NSRange(location: 0, length: min(100, textView.string.count))
                    textView.scrollRangeToVisible(range)
                }
                
                // 更新頂部裝飾條
                if let topBarView = self.topBarView {
                    topBarView.isHidden = false
                    topBarView.alphaValue = 1.0
                    topBarView.needsDisplay = true
                    
                    // 確保頂部裝飾條在視窗最上層
                    if let superview = topBarView.superview {
                        superview.addSubview(topBarView)
                    }
                }
            }
        } else if heightDifference > 0 {
            // 即使不做尺寸調整，也確保滾動到可見區域
            let range = NSRange(location: 0, length: min(100, textView.string.count))
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
    
    deinit {
        // 在deinit中不使用閉包或Task，直接清理資源
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
            .info("TextWindowManager 開始釋放資源")
        
        // 先停止定時器
        if let timer = topBarFixTimer {
            timer.invalidate()
        }
        topBarFixTimer = nil
        
        // 清理觀察者
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        
        // 清理鍵盤監聽器
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        keyboardMonitor = nil
        
        // 清理視圖引用
        topBarView = nil
        controlsContainerView = nil
        topContainer = nil
        statsView = nil
        statsContainer = nil
        
        // 釋放結果
        completeResult = nil
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
            .info("TextWindowManager 釋放完成，所有資源已清理")
    }

    // 在窗口調整大小時也更新頂部三色條紋
    private func updateTopColorBar() {
        do {
            try safeUpdateTopColorBar()
        } catch {
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .error("更新頂部色彩條失敗: \(error.localizedDescription)")
        }
    }

    // 新增安全版本的三色條紋更新方法
    private func safeUpdateTopColorBar() throws {
        guard let window = appDelegate?.textWindow,
              let topBarView = self.topBarView,
              topBarView.wantsLayer,
              let topBarLayer = topBarView.layer?.sublayers?.first else { 
            throw NSError(domain: "TextWindowManager", code: 100, userInfo: [NSLocalizedDescriptionKey: "無法更新頂部條紋：組件不完整"])
        }
        
        // 檢查layer是否有需要的子layer
        if topBarLayer.sublayers?.count != 3 {
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .warning("三色條紋層次結構不正確，重建...")
            
            // 清除現有子層
            topBarLayer.sublayers?.forEach { sublayer in
                sublayer.removeFromSuperlayer()
            }
            
            // 設置新的大小
            let newWidth = window.frame.width
            topBarLayer.frame.size.width = newWidth
            
            // 重新創建三色條紋
            let redLayer = CALayer()
            redLayer.backgroundColor = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9).cgColor
            redLayer.frame = CGRect(x: 0, y: 0, width: newWidth/3, height: 5)
            
            let yellowLayer = CALayer()
            yellowLayer.backgroundColor = NSColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 0.9).cgColor
            yellowLayer.frame = CGRect(x: newWidth/3, y: 0, width: newWidth/3, height: 5)
            
            let greenLayer = CALayer()
            greenLayer.backgroundColor = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 0.9).cgColor
            greenLayer.frame = CGRect(x: 2*newWidth/3, y: 0, width: newWidth/3, height: 5)
            
            topBarLayer.addSublayer(redLayer)
            topBarLayer.addSublayer(yellowLayer)
            topBarLayer.addSublayer(greenLayer)
            
            return
        }
        
        // 如果子層完整，只需更新大小
        let newWidth = window.frame.width
        topBarLayer.frame.size.width = newWidth
        
        if let redLayer = topBarLayer.sublayers?[0],
           let yellowLayer = topBarLayer.sublayers?[1],
           let greenLayer = topBarLayer.sublayers?[2] {
            
            redLayer.frame = CGRect(x: 0, y: 0, width: newWidth/3, height: 5)
            yellowLayer.frame = CGRect(x: newWidth/3, y: 0, width: newWidth/3, height: 5)
            greenLayer.frame = CGRect(x: 2*newWidth/3, y: 0, width: newWidth/3, height: 5)
        }
    }

    // 新增一個方法處理頂部條更新邏輯
    @MainActor
    private func updateTopBarVisibility() {
        // 增加錯誤處理和安全檢查
        do {
            // 檢查appDelegate是否存在
            guard let appDelegate = self.appDelegate else {
                // appDelegate不存在，停止定時器
                self.topBarFixTimer?.invalidate()
                self.topBarFixTimer = nil
                return
            }
            
            // 檢查window是否存在且可見
            guard let window = appDelegate.textWindow,
                  window.isVisible else {
                // 窗口不存在或不可見，停止定時器
                self.topBarFixTimer?.invalidate()
                self.topBarFixTimer = nil
                return
            }
            
            // 檢查contentView是否存在
            guard let contentView = window.contentView else {
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .error("窗口的contentView不存在，停止定時器")
                self.topBarFixTimer?.invalidate()
                self.topBarFixTimer = nil
                return
            }
            
            // 檢查topContainer是否存在
            guard let topContainer = self.topContainer else {
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .error("頂部容器不存在，停止定時器")
                self.topBarFixTimer?.invalidate()
                self.topBarFixTimer = nil
                return
            }
            
            // 檢查topContainer是否仍在視圖層次結構中
            if topContainer.superview == nil {
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .warning("頂部容器已從視圖層次結構中移除，重新添加...")
                
                // 安全地添加topContainer
                contentView.addSubview(topContainer)
                
                // 重新設置約束
                NSLayoutConstraint.activate([
                    topContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
                    topContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    topContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    topContainer.heightAnchor.constraint(equalToConstant: 33)
                ])
            }
            
            // 安全檢查topBarView
            if let topBarView = self.topBarView, topBarView.superview != nil {
                if topBarView.isHidden || topBarView.alphaValue < 1.0 {
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .warning("頂部裝飾條不可見，重新顯示...")
                    topBarView.isHidden = false
                    topBarView.alphaValue = 1.0
                    
                    // 安全地更新三色條紋
                    try self.safeUpdateTopColorBar()
                }
            }
            
            // 安全檢查控制按鈕容器
            if let controlsContainer = self.controlsContainerView, controlsContainer.superview != nil {
                if controlsContainer.isHidden || controlsContainer.alphaValue < 1.0 {
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .warning("控制按鈕容器不可見或透明，重新設置...")
                    controlsContainer.isHidden = false
                    controlsContainer.alphaValue = 1.0
                }
                
                // 安全地設置背景顏色
                if controlsContainer.wantsLayer && 
                   (controlsContainer.layer?.backgroundColor == nil) {
                    controlsContainer.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
                }
            }
            
            // 安全檢查頂部容器背景色
            if topContainer.wantsLayer && 
               (topContainer.layer?.backgroundColor == nil || topContainer.alphaValue < 1.0) {
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                    .warning("頂部容器背景顏色丟失，重新設置...")
                topContainer.layer?.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
                topContainer.alphaValue = 1.0
            }
            
            // 確保topContainer在最上層，但要避免不必要的子視圖重排
            if topContainer.superview == contentView &&
               contentView.subviews.last !== topContainer {
                contentView.addSubview(topContainer)
            }
        } catch {
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .error("定時器更新頂部框框時發生錯誤: \(error.localizedDescription)")
            
            // 發生錯誤時停止定時器以防止持續崩潰
            self.topBarFixTimer?.invalidate()
            self.topBarFixTimer = nil
        }
    }

    // 修改為一個異步版本的updateTopBarVisibility方法
    @MainActor
    private func updateTopBarVisibilityAsync() {
        self.updateTopBarVisibility()
    }

    // 動畫文字流動效果
    @MainActor
    private func animateTextStream(attributedString: NSAttributedString, textView: NSTextView, window: NSWindow) async {
        // 先預調整視窗大小以避免彈跳
        await preResizeWindowForText(attributedString: attributedString, textView: textView, window: window)
        
        // 設置基本段落樣式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 12
        paragraphStyle.paragraphSpacing = 16
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        // 清空現有內容
        let emptyAttributedString = NSAttributedString(
            string: "",
            attributes: [
                .font: self.getPungyuFont(size: 22),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(emptyAttributedString)
        textView.textStorage?.endEditing()
        
        // 以較小的塊大小進行文字流動，創造真正的流動效果
        let chunkSize = 1 // 每次添加1個字符
        let streamDelay = 0.015 // 15ms間隔，可見的流動效果
        
        let totalLength = attributedString.length
        var currentIndex = 0
        
        while currentIndex < totalLength {
            let endIndex = min(currentIndex + chunkSize, totalLength)
            let range = NSRange(location: currentIndex, length: endIndex - currentIndex)
            let chunk = attributedString.attributedSubstring(from: range)
            
            // 添加字符到文本視圖
            textView.textStorage?.beginEditing()
            textView.textStorage?.append(chunk)
            textView.textStorage?.endEditing()
            
            // 保持滾動到最底部
            textView.scrollToEndOfDocument(nil)
            
            // 更新視窗
            window.update()
            
            currentIndex = endIndex
            
            // 等待間隔
            try? await Task.sleep(nanoseconds: UInt64(streamDelay * 1_000_000_000))
        }
        
        Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
            .info("文字流動完成，總字符數: \(totalLength)")
    }
    
    // 預調整視窗大小以避免彈跳
    @MainActor
    private func preResizeWindowForText(attributedString: NSAttributedString, textView: NSTextView, window: NSWindow) async {
        // 計算文字所需的高度
        let textContainer = textView.textContainer
        let _ = textView.layoutManager
        
        // 臨時計算文字高度
        let tempTextStorage = NSTextStorage(attributedString: attributedString)
        let tempLayoutManager = NSLayoutManager()
        let tempTextContainer = NSTextContainer(size: textContainer?.size ?? NSSize.zero)
        
        tempTextStorage.addLayoutManager(tempLayoutManager)
        tempLayoutManager.addTextContainer(tempTextContainer)
        
        // 計算所需高度
        tempLayoutManager.glyphRange(for: tempTextContainer)
        let textHeight = tempLayoutManager.usedRect(for: tempTextContainer).height
        
        // 加上內邊距和額外空間
        let totalHeight = textHeight + textView.textContainerInset.height * 2 + 100
        
        // 獲取當前視窗框架
        let currentFrame = window.frame
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        // 計算新的視窗高度，但不超過螢幕高度的80%
        let maxHeight = screenFrame.height * 0.8
        let newHeight = min(totalHeight, maxHeight)
        
        // 如果高度變化顯著，則調整視窗大小
        if abs(newHeight - currentFrame.height) > 50 {
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + currentFrame.height - newHeight,
                width: currentFrame.width,
                height: newHeight
            )
            
            // 平滑調整視窗大小
            await withCheckedContinuation { continuation in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.setFrame(newFrame, display: true, animate: true)
                }) {
                    continuation.resume()
                }
            }
            
            // 等待動畫完成
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .info("視窗預調整完成，新高度: \(newHeight)")
        }
    }

    // 添加統一的統計信息更新方法
    private func updateStatisticsInfo(originalText: String, correctedText: String) {
        // 安全檢查，確保在主線程更新UI
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateStatisticsInfo(originalText: originalText, correctedText: correctedText)
            }
            return
        }
        
        // 找到統計信息視圖
        if let statsView = self.statsView, let container = self.statsContainer {
            // 更新統計信息
            self.updateTextStatistics(originalText: originalText, correctedText: correctedText, statsView: statsView)
            
            // 確保容器是可見的
            if container.alphaValue == 0 {
                container.alphaValue = 1.0 // 直接設置，避免使用動畫上下文
            }
        } else {
            // 嘗試通過標識符查找
            Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                .warning("找不到已保存的統計視圖引用，嘗試通過標識符查找")
            
            if let appDelegate = self.appDelegate {
                let allViews = appDelegate.textWindow?.contentView?.subviews.flatMap { view in 
                    return self.getAllSubviews(view: view) 
                } ?? []
                
                let foundStatsView = allViews.first(where: { textField in 
                    return (textField as? NSTextField)?.identifier?.rawValue == "statsView" 
                }) as? NSTextField
                
                let foundContainer = foundStatsView?.superview
                
                if let foundStatsView = foundStatsView, let container = foundContainer {
                    // 更新引用以便下次使用
                    self.statsView = foundStatsView
                    self.statsContainer = container
                    
                    // 更新統計資訊
                    self.updateTextStatistics(originalText: originalText, correctedText: correctedText, statsView: foundStatsView)
                    
                    // 確保容器是可見的
                    if container.alphaValue == 0 {
                        container.alphaValue = 1.0
                    }
                } else {
                    Logger(subsystem: "com.yourcompany.TextCorrection", category: "TextWindowManager")
                        .error("無法找到 statsView，統計信息未更新")
                }
            }
        }
    }

    /// 檢查管理器是否已被銷毀或無效
    var isDestroyed: Bool {
        // 檢查視窗是否已關閉
        if let textWindow = appDelegate?.textWindow, !textWindow.isVisible {
            return true
        }
        
        // 檢查視圖是否已從視圖層次結構中移除
        if let textView = appDelegate?.currentTextView, textView.isDestroyed {
            return true
        }
        
        return false
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