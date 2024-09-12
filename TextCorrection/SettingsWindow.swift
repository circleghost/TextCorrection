import Cocoa

class SettingsWindow: NSWindow {
    private var apiKeyTextField: NSTextField!
    private var saveButton: NSButton!
    private var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        super.init(contentRect: NSRect(x: 100, y: 100, width: 300, height: 150),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered,
                   defer: false)
        
        self.title = "設定"
        self.center()
        
        setupUI()
    }
    
    private func setupUI() {
        let contentView = NSView(frame: self.contentView!.bounds)
        
        apiKeyTextField = NSTextField(frame: NSRect(x: 20, y: 80, width: 260, height: 24))
        apiKeyTextField.placeholderString = "輸入 OpenAI API 金鑰"
        contentView.addSubview(apiKeyTextField)
        
        saveButton = NSButton(frame: NSRect(x: 20, y: 20, width: 100, height: 32))
        saveButton.title = "儲存"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveButtonClicked)
        contentView.addSubview(saveButton)
        
        self.contentView = contentView
        
        // 載入已儲存的 API 金鑰
        if let apiKey = appDelegate?.getStoredApiKey() {
            apiKeyTextField.stringValue = apiKey
        }
    }
    
    @objc private func saveButtonClicked() {
        let apiKey = apiKeyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        appDelegate?.testAndSaveApiKey(apiKey)
        self.close()
    }
}