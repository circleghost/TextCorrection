import Cocoa
import os.log
import Combine

class PasteboardManager: @unchecked Sendable {
    weak var appDelegate: AppDelegate?
    private var lastPasteboardChangeCount: Int = 0
    private var timer: Timer?
    private var isObserving: Bool = false
    private var lastProcessedString: String? = nil
    // 添加新標誌來暫時禁用監視
    private var temporarilyDisabled: Bool = false
    // 添加標誌來記錄熱鍵觸發的剪貼板變化
    private var isHotkeyTriggeredChange: Bool = false
    
    // 創建日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "PasteboardManager")
    
    // 訂閱集合
    private var cancellables = Set<AnyCancellable>()
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        logger.info("PasteboardManager 初始化")
        
        // 訂閱AppState的剪貼板監控設定
        setupSubscriptions()
        
        // 監聽熱鍵觸發的通知
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(hotkeyTriggered), 
                                              name: NSNotification.Name("HotkeyTriggered"), 
                                              object: nil)
    }
    
    // 熱鍵觸發時的處理
    @objc func hotkeyTriggered() {
        logger.info("收到熱鍵觸發通知，標記下一個剪貼板變化為熱鍵觸發")
        isHotkeyTriggeredChange = true
        
        // 2秒後重置標誌，以防萬一
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isHotkeyTriggeredChange = false
        }
    }
    
    private func setupSubscriptions() {
        // 監聽剪貼板監控設定的變化
        AppState.shared.$isClipboardMonitoringEnabled
            .sink { [weak self] isEnabled in
                guard let self = self else { return }
                
                if isEnabled && !self.isObserving {
                    self.startMonitoring()
                } else if !isEnabled && self.isObserving {
                    self.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }
    
    // 開始監控剪貼板 (公開方法)
    func startMonitoring() {
        if !isObserving {
            logger.info("開始監控剪貼板")
            setupPasteboardObserver()
        }
    }
    
    // 停止監控剪貼板 (公開方法)
    func stopMonitoring() {
        if isObserving {
            logger.info("停止監控剪貼板")
            stopObserving()
        }
    }
    
    func setupPasteboardObserver() {
        // 確保停止任何現有的觀察器
        stopObserving()
        
        // 初始化剪貼板變更計數
        self.lastPasteboardChangeCount = NSPasteboard.general.changeCount
        logger.info("設置剪貼板觀察器，初始計數: \(self.lastPasteboardChangeCount)")
        
        // 將當前剪貼板內容保存為最後處理的字符串，避免重複處理
        self.lastProcessedString = NSPasteboard.general.string(forType: .string)
        
        // 在主線程上檢查當前剪貼板
        DispatchQueue.main.async { [weak self] in
            self?.checkCurrentClipboard()
        }
        
        isObserving = true
        
        // 創建定時器，使用較低頻率以避免過高的CPU使用率
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, self.isObserving else { return }
            
            // 如果暫時禁用，則跳過檢查
            if self.temporarilyDisabled {
                return
            }
            
            // 在主線程檢查剪貼板變化以避免線程問題
            let currentChangeCount = NSPasteboard.general.changeCount
            
            if currentChangeCount != self.lastPasteboardChangeCount {
                self.lastPasteboardChangeCount = currentChangeCount
                self.logger.info("檢測到剪貼板變化，新計數: \(currentChangeCount)")
                
                // 更新AppState中的剪貼板變更時間
                AppState.shared.lastClipboardChangeTime = Date()
                
                // 為防止頻繁處理相同內容，使用延遲執行
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.checkCurrentClipboard()
                }
            }
        }
        
        // 確保計時器運行在選擇的 runloop 模式下
        RunLoop.main.add(timer!, forMode: .common)
        logger.info("剪貼板觀察器設置完成")
    }
    
    // 檢查當前剪貼板內容並處理
    private func checkCurrentClipboard() {
        // 如果暫時禁用，則跳過檢查
        if temporarilyDisabled {
            return
        }
        
        // 檢查剪貼板內容是否為文字
        guard let clipboardString = NSPasteboard.general.string(forType: .string), !clipboardString.isEmpty else {
            self.logger.info("剪貼板內容不是文字或為空")
            return
        }
        
        // 即使是相同的文字，也記錄並允許處理
        let isSameAsLast = clipboardString == lastProcessedString
        if isSameAsLast {
            self.logger.info("剪貼板內容與上次相同，仍將顯示按鈕")
        }
        
        // 總是更新最後處理的字符串
        self.lastProcessedString = clipboardString
        self.logger.info("剪貼板包含文字，長度: \(clipboardString.count)")
        
        // 通知有新文本被複製
        AppKitBridge.shared.notifyTextCopied(clipboardString)
        self.logger.info("通知新文本被複製，長度: \(clipboardString.count)")
        
        // 檢查是否是熱鍵觸發的剪貼板變化
        if isHotkeyTriggeredChange {
            self.logger.info("檢測到熱鍵觸發的剪貼板變化，不顯示浮動按鈕")
            isHotkeyTriggeredChange = false
            return
        }
        
        // 對任何非空文本顯示浮動按鈕 (不論是否重複)
        DispatchQueue.main.async { [weak self] in
            // 只有有足夠字符的文本才值得校正
            if clipboardString.count > 5 {
                // 使用AppDelegate顯示浮動按鈕
                self?.appDelegate?.showFloatingButton()
            }
        }
    }
    
    // 暫時禁用剪貼板監視 (例如，當應用主動觸發複製操作時)
    func temporarilyDisable() {
        temporarilyDisabled = true
        logger.info("剪貼板監視暫時禁用")
        
        // 2秒後自動重新啟用
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.temporarilyDisabled = false
            self.logger.info("剪貼板監視重新啟用")
            // 更新最後處理的字符串和計數，避免處理在禁用期間發生的變化
            self.lastProcessedString = NSPasteboard.general.string(forType: .string)
            self.lastPasteboardChangeCount = NSPasteboard.general.changeCount
        }
    }
    
    // 停止監聽
    func stopObserving() {
        isObserving = false
        timer?.invalidate()
        timer = nil
        logger.info("停止剪貼板觀察")
    }
    
    // 重新開始監聽
    func restartObserving() {
        stopObserving()
        setupPasteboardObserver()
        logger.info("重新啟動剪貼板觀察")
    }
    
    // 清理資源
    deinit {
        stopObserving()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        logger.info("PasteboardManager 已釋放")
    }
}