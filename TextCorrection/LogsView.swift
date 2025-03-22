import SwiftUI

/// 日誌查看器視圖
struct LogsView: View {
    @StateObject private var viewModel = LogsViewModel()
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 頂部控制欄
            HStack {
                Picker("日誌級別", selection: $viewModel.selectedLevel) {
                    Text("全部").tag(nil as LogManager.LogLevel?)
                    ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level as LogManager.LogLevel?)
                    }
                }
                .frame(width: 120)
                
                Divider()
                    .frame(height: 20)
                
                Picker("類別", selection: $viewModel.selectedCategory) {
                    Text("全部").tag(nil as String?)
                    ForEach(viewModel.categories, id: \.self) { category in
                        Text(category).tag(category as String?)
                    }
                }
                .frame(width: 150)
                
                Spacer()
                
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("搜索日誌", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                        .onChange(of: searchText) { oldValue, newValue in
                            viewModel.searchText = newValue
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            viewModel.searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                
                Spacer()
                
                // 操作按鈕
                HStack(spacing: 15) {
                    Button(action: viewModel.refreshLogs) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新日誌")
                    
                    Button(action: viewModel.clearLogs) {
                        Image(systemName: "trash")
                    }
                    .help("清空日誌")
                    
                    Button(action: exportLogs) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("匯出日誌")
                    
                    Button(action: createReport) {
                        Image(systemName: "doc.zipper")
                    }
                    .help("創建診斷報告")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 日誌列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.filteredLogs) { entry in
                        LogEntryRow(entry: entry)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(rowBackground(for: entry.level))
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // 底部狀態欄
            HStack {
                Text("共 \(viewModel.filteredLogs.count) 條日誌")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 最小日誌級別設置
                HStack {
                    Text("最小記錄級別:")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.minimumLogLevel) {
                        ForEach(LogManager.LogLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .frame(width: 100)
                    .onChange(of: viewModel.minimumLogLevel) { oldValue, newValue in
                        LogManager.shared.setMinimumLogLevel(newValue)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 800, height: 600)
        .onAppear {
            viewModel.refreshLogs()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    /// 根據日誌級別獲取行背景顏色
    private func rowBackground(for levelString: String) -> Color {
        guard let level = LogManager.LogLevel(rawValue: levelString) else {
            return Color.clear
        }
        
        switch level {
        case .debug:
            return Color.clear
        case .info:
            return Color.clear
        case .notice:
            return Color.blue.opacity(0.1)
        case .warning:
            return Color.yellow.opacity(0.2)
        case .error:
            return Color.red.opacity(0.2)
        case .fault:
            return Color.red.opacity(0.3)
        }
    }
    
    /// 匯出日誌
    private func exportLogs() {
        if let url = LogManager.shared.shareLogs() {
            shareURL = url
            showingShareSheet = true
        }
    }
    
    /// 創建診斷報告
    private func createReport() {
        if let url = LogManager.shared.exportDiagnosticReport() {
            shareURL = url
            showingShareSheet = true
        }
    }
}

/// 單條日誌條目行
struct LogEntryRow: View {
    let entry: LogManager.LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 時間戳
                Text(formatDate(entry.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // 級別
                Text(entry.level.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(levelColor(for: entry.level))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(levelColor(for: entry.level).opacity(0.1))
                    .cornerRadius(4)
                
                // 類別
                Text(entry.category)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 展開/收起按鈕
                Button(action: {
                    isExpanded.toggle()
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            // 消息
            Text(entry.message)
                .font(.system(.caption, design: isExpanded ? .monospaced : .default))
                .lineLimit(isExpanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }
    
    /// 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    /// 根據日誌級別獲取顏色
    private func levelColor(for levelString: String) -> Color {
        guard let level = LogManager.LogLevel(rawValue: levelString) else {
            return .primary
        }
        
        switch level {
        case .debug:
            return .gray
        case .info:
            return .blue
        case .notice:
            return .green
        case .warning:
            return .orange
        case .error, .fault:
            return .red
        }
    }
}

/// 分享表單
struct ShareSheet: NSViewRepresentable {
    var items: [Any]
    
    func makeNSView(context: Context) -> NSView {
        // 創建一個容器視圖
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 當視圖更新時，顯示分享選擇器
        guard let items = items as? [URL], let url = items.first else { return }
        
        // 在下一個運行循環中顯示檔案
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// 日誌視圖模型
class LogsViewModel: ObservableObject {
    @Published var logs: [LogManager.LogEntry] = []
    @Published var filteredLogs: [LogManager.LogEntry] = []
    @Published var selectedLevel: LogManager.LogLevel? = nil {
        didSet { filterLogs() }
    }
    @Published var selectedCategory: String? = nil {
        didSet { filterLogs() }
    }
    @Published var searchText: String = "" {
        didSet { filterLogs() }
    }
    @Published var categories: [String] = []
    @Published var minimumLogLevel: LogManager.LogLevel = .info
    
    init() {
        refreshLogs()
        minimumLogLevel = LogManager.shared.minimumLogLevel
    }
    
    /// 刷新日誌
    func refreshLogs() {
        logs = LogManager.shared.logEntries
        categories = LogManager.shared.getAllCategories()
        filterLogs()
    }
    
    /// 過濾日誌
    private func filterLogs() {
        filteredLogs = LogManager.shared.getFilteredLogs(
            level: selectedLevel,
            category: selectedCategory,
            searchText: searchText
        )
    }
    
    /// 清空日誌
    func clearLogs() {
        LogManager.shared.clearLogs()
        refreshLogs()
    }
}

struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        LogsView()
    }
} 