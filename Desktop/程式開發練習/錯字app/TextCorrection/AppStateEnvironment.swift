import Foundation
import SwiftUI

// MARK: - AppState Environment Key

/// 為AppState提供的環境鍵
struct AppStateKey: EnvironmentKey {
    static let defaultValue = AppState.shared
}

/// 為AppStateObserver提供的環境鍵
struct AppStateObserverKey: EnvironmentKey {
    // 理論上我們不應該在這裡創建默認值，因為AppStateObserver需要一個AppState實例
    // 但是為了符合EnvironmentKey協議，我們提供一個默認值
    static let defaultValue = AppStateObserver(appState: AppState.shared)
}

// MARK: - Environment Values 擴展

extension EnvironmentValues {
    /// 訪問環境中的AppState實例
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
    
    /// 訪問環境中的AppStateObserver實例
    var appStateObserver: AppStateObserver {
        get { self[AppStateObserverKey.self] }
        set { self[AppStateObserverKey.self] = newValue }
    }
}

// MARK: - View 擴展

extension View {
    /// 將AppState和對應的Observer添加到環境中
    /// - Parameter appState: 要使用的AppState實例
    /// - Returns: 修改後的視圖
    func withAppState(_ appState: AppState = AppState.shared) -> some View {
        let observer = AppStateObserver(appState: appState)
        return self
            .environmentObject(observer)
            .environment(\.appState, appState)
            .environment(\.appStateObserver, observer)
    }
} 