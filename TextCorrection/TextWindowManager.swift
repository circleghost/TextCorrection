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
        
        // 設置標題字體和大小
        if let titleFont = NSFont(name: "Yuanti TC", size: 18) {
            appDelegate.textWindow?.titleVisibility = .visible
            appDelegate.textWindow?.titlebarAppearsTransparent = false
            appDelegate.textWindow?.styleMask.insert(.titled)
            
            if let titleView = appDelegate.textWindow?.standardWindowButton(.closeButton)?.superview {
                titleView.wantsLayer = true
                titleView.layer?.backgroundColor = NSColor(hexString: "#1E1E26")?.cgColor
                
                let titleLabel = NSTextField(labelWithString: "AI 潤飾")
                titleLabel.font = titleFont
                titleLabel.textColor = .white
                titleLabel.alignment = .center
                titleLabel.backgroundColor = .clear
                titleLabel.isBordered = false
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
        scrollView.documentView = textView

        // 統信息
        let statsContainer = NSView()
        statsContainer.translatesAutoresizingMaskIntoConstraints = false
        mainArea.addSubview(statsContainer)

        let statsView = NSTextField()
        statsView.translatesAutoresizingMaskIntoConstraints = false
        statsView.isEditable = false
        statsView.isBordered = false
        statsView.backgroundColor = .clear
        statsView.textColor = NSColor.lightGray
        statsView.font = NSFont.systemFont(ofSize: 12)
        statsView.stringValue = ""
        statsView.lineBreakMode = .byTruncatingTail
        statsContainer.addSubview(statsView)

        let shortcutView = NSTextField()
        shortcutView.translatesAutoresizingMaskIntoConstraints = false
        shortcutView.isEditable = false
        shortcutView.isBordered = false
        shortcutView.backgroundColor = .clear
        shortcutView.textColor = NSColor.lightGray
        shortcutView.font = NSFont.systemFont(ofSize: 12)
        shortcutView.stringValue = "複製文字 ⌘+C"
        shortcutView.alignment = .right
        statsContainer.addSubview(shortcutView)

        // 底部區域
        let bottomArea = NSView()
        bottomArea.translatesAutoresizingMaskIntoConstraints = false
        bottomArea.wantsLayer = true
        bottomArea.layer?.backgroundColor = NSColor(hexString: "#28252E")?.withAlphaComponent(0.95).cgColor
        contentView.addSubview(bottomArea)

        let actionContainer = NSView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.wantsLayer = true
        actionContainer.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1.0).cgColor
        actionContainer.layer?.cornerRadius = 10
        bottomArea.addSubview(actionContainer)

        let copyButton = NSButton(title: "複製並貼上", target: appDelegate, action: #selector(appDelegate.copyAndPasteRewrittenText))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        copyButton.contentTintColor = .white
        actionContainer.addSubview(copyButton)

        let enterSymbol = NSTextField(labelWithString: "⏎")
        enterSymbol.translatesAutoresizingMaskIntoConstraints = false
        enterSymbol.font = NSFont.systemFont(ofSize: 16)
        enterSymbol.textColor = .white
        enterSymbol.backgroundColor = .clear
        enterSymbol.isBordered = false
        actionContainer.addSubview(enterSymbol)

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
            actionContainer.heightAnchor.constraint(equalToConstant: 36),
            actionContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            copyButton.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: 10),
            copyButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: enterSymbol.leadingAnchor, constant: -5),

            enterSymbol.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor, constant: -10),
            enterSymbol.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
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

    // 修改這個方法
    func updateTextViewWithDiff(originalText: String, newText: String, textView: NSTextView) {
        let attributedString = NSMutableAttributedString()
        
        let diff = TextProcessing.diffStrings(originalText, newText)
        
        // 合併相鄰的相同類型的變更
        let mergedDiff = diff.reduce(into: [TextProcessing.DiffChange]()) { result, change in
            if case .equal(let text) = change, let last = result.last, case .equal(let prevText) = last {
                result[result.count - 1] = .equal(prevText + text)
            } else if case .insert(let text) = change, let last = result.last, case .insert(let prevText) = last {
                result[result.count - 1] = .insert(prevText + text)
            } else if case .delete(let text) = change, let last = result.last, case .delete(let prevText) = last {
                result[result.count - 1] = .delete(prevText + text)
            } else {
                result.append(change)
            }
        }
        
        // 使用合併後的差異重新生成 attributedString
        for change in mergedDiff {
            switch change {
            case .equal(let text):
                attributedString.append(NSAttributedString(string: text))
            case .insert(let text):
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.green,
                    .backgroundColor: NSColor.green.withAlphaComponent(0.2)
                ]
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            case .delete(let text):
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.red,
                    .backgroundColor: NSColor.red.withAlphaComponent(0.2),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        
        DispatchQueue.main.async {
            textView.textStorage?.setAttributedString(attributedString)
        }
    }
}