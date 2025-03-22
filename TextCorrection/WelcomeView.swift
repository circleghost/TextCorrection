import SwiftUI

/// 歡迎頁面，為使用者提供應用程式的基本介紹和使用指南
struct WelcomeView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @State private var currentPage = 0
    
    private let totalPages = 2 // 只有 2 頁
    
    // 提供一個無參數初始化方法，用於 AppDelegate 中建立 WelcomeView
    init() {
        self._isPresented = .constant(true)
    }
    
    // 原始初始化方法
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    var body: some View {
        ZStack {
            // 簡單的背景 (macOS 可以用顏色或漸層)
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 頂部標題區域
                Text("歡迎使用錯字修正工具")
                    .font(Font.pungyu(size: 32, weight: .bold))
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                
                // 自訂的頁面指示器
                HStack(spacing: 10) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.blue : Color.gray.opacity(0.5))
                            .frame(width: 10, height: 10)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .animation(.spring(), value: currentPage)
                    }
                }
                .padding(.bottom, 20)
                
                // 內容區域 - TabView (macOS用 DefaultTabViewStyle)
                TabView(selection: $currentPage) {
                    clipboardFeaturePage
                        .tag(0)
                    
                    hotkeyFeaturePage
                        .tag(1)
                }
                .tabViewStyle(DefaultTabViewStyle())
                .frame(height: 420)
                
                Spacer(minLength: 20)
                
                // 底部按鈕區域
                HStack {
                    // 上一頁
                    Button {
                        if currentPage > 0 {
                            withAnimation {
                                currentPage -= 1
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("上一頁")
                        }
                    }
                    .buttonStyle(
                        NavigationButtonStyle(
                            isEnabled: currentPage > 0,
                            isPrimary: false
                        )
                    )
                    
                    Spacer()
                    
                    // 下一頁或開始使用
                    Button {
                        if currentPage < totalPages - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            // 最後一頁，關閉指南
                            appState.markWelcomeScreenAsShown()
                            isPresented = false
                        }
                    } label: {
                        HStack {
                            Text(currentPage < totalPages - 1 ? "下一頁" : "開始使用")
                            if currentPage < totalPages - 1 {
                                Image(systemName: "arrow.right")
                            } else {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(
                        NavigationButtonStyle(
                            isEnabled: true,
                            isPrimary: true
                        )
                    )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            // 固定視窗大小 (若需要彈性，可改成 .frame(minWidth:, minHeight:) )
            .frame(width: 800, height: 650)
        }
    }
    
    // MARK: - 第一頁：複製懸浮按鈕功能介紹
    private var clipboardFeaturePage: some View {
        VStack(spacing: 30) {
            Image(systemName: "doc.on.clipboard")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            Text("複製文字功能")
                .font(.system(size: 28, weight: .bold))
            
            VStack(alignment: .leading, spacing: 20) {
                featureExplanation(
                    step: "1",
                    title: "選取並複製文字",
                    description: "在任何應用程式中，選取想要校正的文字，然後按下 Command + C 複製。",
                    icon: "text.cursor"
                )
                
                featureExplanation(
                    step: "2",
                    title: "點擊懸浮按鈕",
                    description: "複製後會顯示懸浮按鈕，點擊按鈕開始校正文字。",
                    icon: "hand.tap"
                )
                
                featureExplanation(
                    step: "3",
                    title: "查看校正結果",
                    description: "系統會自動校正文字並顯示結果，可以直接複製修改後的內容。",
                    icon: "checkmark.bubble"
                )
            }
            .padding(.horizontal, 40)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 第二頁：熱鍵功能說明
    private var hotkeyFeaturePage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "keyboard")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                    .padding(.top, 10)
                
                Text("熱鍵快速校正")
                    .font(.system(size: 28, weight: .bold))
                
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .center) {
                        Text("快速鍵組合")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Ctrl + Shift + 空白鍵")
                            .font(.system(size: 20, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                    }
                    .padding(.bottom, 5)
                    
                    Text("直接校正選中文字")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.bottom, 5)
                    
                    Text("選中任何文字，按下組合鍵立即開始校正，無需複製步驟。")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 5)
                    
                    Divider()
                        .padding(.vertical, 5)
                    
                    Text("提示：")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.bottom, 5)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        bulletPoint(text: "校正過程中，狀態欄圖示會顯示處理狀態")
                        bulletPoint(text: "完成校正後，你可以查看變更並一鍵複製結果")
                        bulletPoint(text: "如果需要調整設定，請點擊狀態欄圖示選擇「設定」")
                    }
                    
                    Button(action: {
                        // 使用 AppKitBridge 統一打開設定窗口
                        AppKitBridge.shared.showSettingsWindow()
                    }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("開啟設定")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 10)
                }
                .padding(.horizontal, 40)
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 420)
    }
    
    // MARK: - 功能說明項目 - 優化視覺呈現
    private func featureExplanation(
        step: String,
        title: String,
        description: String,
        icon: String
    ) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                
                Text(step)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                }
                
                Text(description)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - 項目符號
    private func bulletPoint(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.system(size: 18))
                .foregroundColor(.blue)
            
            Text(text)
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 自訂按鈕樣式，讓「上一頁」與「下一頁 / 開始使用」風格一致
struct NavigationButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isEnabled
                        ? (isPrimary ? Color.blue : Color.blue.opacity(0.7))
                        : Color.gray.opacity(0.5)
                    )
            )
            .foregroundColor(.white)
            // 按下時做一點透明度變化
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            // 移除 onTapGesture，以免蓋掉原本 Button(action:) 的動作
            .disabled(!isEnabled)
    }
}

// MARK: - 預覽
#Preview {
    WelcomeView(isPresented: .constant(true))
        .environmentObject(AppState.shared)
}
