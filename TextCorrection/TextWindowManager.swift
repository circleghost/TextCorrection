import Cocoa

class TextWindowManager {
    weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func showTextWindow(text: String) {
        guard let appDelegate = appDelegate else { return }
        
        appDelegate.resetWindowState()
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        // 設定視窗大小為螢幕的 50% 寬度和 25% 高度
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
        appDelegate.textWindow?.title = "AI 潤飾"
        appDelegate.textWindow?.titlebarAppearsTransparent = false
        appDelegate.textWindow?.isMovableByWindowBackground = true
        
        // 添加霧化效果
        let visualEffect = NSVisualEffectView(frame: adjustedFrame)
        visualEffect.material = .windowBackground
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        
        appDelegate.textWindow?.contentView = visualEffect
        appDelegate.textWindow?.backgroundColor = NSColor(hexString: "#1E1E26")?.withAlphaComponent(0.6) ?? .black.withAlphaComponent(0.6)
        
        appDelegate.textWindow?.minSize = NSSize(width: 400, height: 250)
        appDelegate.textWindow?.isOpaque = false
        appDelegate.textWindow?.hasShadow = true
        appDelegate.textWindow?.appearance = NSAppearance(named: .darkAqua)
        
        // 設置標題字體和大小
        if let titleFont = NSFont(name: "Yuanti TC", size: 18) {
            appDelegate.textWindow?.standardWindowButton(.closeButton)?.superview?.subviews.forEach { $0.removeFromSuperview() }
            appDelegate.textWindow?.title = "AI 潤飾"
            appDelegate.textWindow?.titleVisibility = .visible
            appDelegate.textWindow?.titlebarAppearsTransparent = false
            appDelegate.textWindow?.styleMask.insert(.titled)
            appDelegate.textWindow?.standardWindowButton(.closeButton)?.superview?.layer?.backgroundColor = NSColor(hexString: "#1E1E26")?.cgColor
            
            if let titleView = appDelegate.textWindow?.standardWindowButton(.closeButton)?.superview {
                titleView.wantsLayer = true
                titleView.layer?.backgroundColor = NSColor(hexString: "#1E1E26")?.cgColor
                
                let titleLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: titleView.frame.width, height: titleView.frame.height))
                titleLabel.stringValue = "AI 潤飾"
                titleLabel.alignment = .center
                titleLabel.font = titleFont
                titleLabel.textColor = .white
                titleLabel.isBezeled = false
                titleLabel.isEditable = false
                titleLabel.drawsBackground = false
                titleView.addSubview(titleLabel)
                
                titleLabel.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    titleLabel.centerXAnchor.constraint(equalTo: titleView.centerXAnchor),
                    titleLabel.centerYAnchor.constraint(equalTo: titleView.centerYAnchor),
                    titleLabel.widthAnchor.constraint(equalTo: titleView.widthAnchor),
                    titleLabel.heightAnchor.constraint(equalTo: titleView.heightAnchor)
                ])
            }
        }
        
        let contentView = NSView(frame: (appDelegate.textWindow?.contentView?.bounds)!)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        appDelegate.textWindow?.contentView?.addSubview(contentView)

        // 移除所有現有的子視圖
        contentView.subviews.forEach { $0.removeFromSuperview() }

        // 主要區域
        let mainArea = NSView()
        mainArea.translatesAutoresizingMaskIntoConstraints = false
        mainArea.identifier = NSUserInterfaceItemIdentifier("mainArea")
        contentView.addSubview(mainArea)

        // 文字區域（圓角）
        let textContainer = NSView()
        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.wantsLayer = true
        textContainer.layer?.backgroundColor = NSColor(hexString: "#2B2B35")?.cgColor
        textContainer.layer?.cornerRadius = 10
        textContainer.identifier = NSUserInterfaceItemIdentifier("textContainer")
        mainArea.addSubview(textContainer)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textContainer.addSubview(scrollView)

        let textView = NSTextView(frame: scrollView.bounds)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.string = text
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 15, height: 15)  // 增加內邊距
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.white
        textView.alignment = .left
        scrollView.documentView = textView

        // 統計信息
        let statsContainer = NSView()
        statsContainer.translatesAutoresizingMaskIntoConstraints = false
        mainArea.addSubview(statsContainer)

        let statsView = NSTextField()
        statsView.translatesAutoresizingMaskIntoConstraints = false
        statsView.isEditable = false
        statsView.isBordered = false
        statsView.backgroundColor = .clear
        statsView.textColor = NSColor(hexString: "#727178") ?? .lightGray
        statsView.font = NSFont.systemFont(ofSize: 12)
        statsView.stringValue = ""
        statsView.lineBreakMode = .byTruncatingTail
        statsContainer.addSubview(statsView)

        let shortcutView = NSTextField()
        shortcutView.translatesAutoresizingMaskIntoConstraints = false
        shortcutView.isEditable = false
        shortcutView.isBordered = false
        shortcutView.backgroundColor = .clear
        shortcutView.textColor = NSColor(hexString: "#727178") ?? .lightGray
        shortcutView.font = NSFont.systemFont(ofSize: 12)
        shortcutView.stringValue = "複製文字 ⌘+C"
        shortcutView.alignment = .right
        statsContainer.addSubview(shortcutView)

        // 底部區域
        let bottomArea = NSView()
        bottomArea.translatesAutoresizingMaskIntoConstraints = false
        bottomArea.wantsLayer = true
        bottomArea.layer?.backgroundColor = NSColor(hexString: "#28252E")?.cgColor
        contentView.addSubview(bottomArea)

        // 複製並貼上按鈕和 Enter 符號容器
        let actionContainer = NSView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomArea.addSubview(actionContainer)

        let copyButton = NSButton()
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.title = "複製並貼上"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        copyButton.target = appDelegate
        copyButton.action = #selector(appDelegate.copyAndPasteRewrittenText)
        copyButton.contentTintColor = .white
        actionContainer.addSubview(copyButton)

        let enterSymbolContainer = NSButton()
        enterSymbolContainer.translatesAutoresizingMaskIntoConstraints = false
        enterSymbolContainer.wantsLayer = true
        enterSymbolContainer.layer?.backgroundColor = NSColor(hexString: "#3B3A42")?.cgColor
        enterSymbolContainer.layer?.cornerRadius = 5
        enterSymbolContainer.target = appDelegate
        enterSymbolContainer.action = #selector(appDelegate.copyAndPasteRewrittenText)
        enterSymbolContainer.title = "⏎"
        enterSymbolContainer.font = NSFont.systemFont(ofSize: 16)
        enterSymbolContainer.contentTintColor = .white
        actionContainer.addSubview(enterSymbolContainer)

        // 設置約束
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: appDelegate.textWindow!.contentView!.bottomAnchor),

            mainArea.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
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
            textView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            statsContainer.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor, constant: 20),
            statsContainer.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor, constant: -20),
            statsContainer.bottomAnchor.constraint(equalTo: bottomArea.topAnchor, constant: -10),
            statsContainer.heightAnchor.constraint(equalToConstant: 20),

            statsView.leadingAnchor.constraint(equalTo: statsContainer.leadingAnchor),
            statsView.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor),

            shortcutView.trailingAnchor.constraint(equalTo: statsContainer.trailingAnchor),
            shortcutView.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor),

            bottomArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomArea.heightAnchor.constraint(equalToConstant: 50),

            actionContainer.trailingAnchor.constraint(equalTo: bottomArea.trailingAnchor, constant: -20),
            actionContainer.centerYAnchor.constraint(equalTo: bottomArea.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: enterSymbolContainer.leadingAnchor, constant: -10),
            copyButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),

            enterSymbolContainer.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            enterSymbolContainer.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            enterSymbolContainer.widthAnchor.constraint(equalToConstant: 30),
            enterSymbolContainer.heightAnchor.constraint(equalToConstant: 30),
        ])
        
        appDelegate.textWindow?.makeKeyAndOrderFront(nil)
        appDelegate.textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        // 替換這幾行
        appDelegate.setTextViewComponents(
            textView: textView,
            originalText: text,
            copyButton: copyButton,
            statsView: statsView,
            shortcutView: shortcutView
        )
        
        // 添加視窗大小變化的監聽器
        NotificationCenter.default.addObserver(appDelegate, selector: #selector(appDelegate.windowDidResize(_:)), name: NSWindow.didResizeNotification, object: appDelegate.textWindow)

        // 設置 textView 的框架大小
        textView.frame = scrollView.bounds
        scrollView.documentView = textView

        // 設置字體
        textView.font = appDelegate.customFont

        // 開始重寫
        appDelegate.rewriteText()

        // 添加鍵盤監聽器
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak appDelegate] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 8 { // Cmd + C
                appDelegate?.copyAndPasteRewrittenText()
                return nil
            } else if event.keyCode == 36 { // Enter
                appDelegate?.copyAndPasteRewrittenText()
                return nil
            }
            return event
        }
    }
}