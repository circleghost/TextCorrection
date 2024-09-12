import SwiftUI

struct PreferencesView: View {
    @AppStorage("OPENAI_API_KEY") private var apiKey: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    var onSave: () -> Void

    var body: some View {
        VStack {
            Text("OpenAI API 金鑰設置")
                .font(.headline)
            SecureField("輸入 API 金鑰", text: $apiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            HStack {
                Button("儲存") {
                    saveApiKey()
                }
                Button("重置") {
                    resetApiKey()
                }
            }
            .padding()
        }
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: Text("通知"), message: Text(alertMessage), dismissButton: .default(Text("確定")))
        }
    }

    private func saveApiKey() {
        if !apiKey.isEmpty {
            UserDefaults.standard.set(apiKey, forKey: "OPENAI_API_KEY")
            alertMessage = "API 金鑰已成功儲存"
            showAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onSave()
            }
        } else {
            alertMessage = "請輸入有效的 API 金鑰"
            showAlert = true
        }
    }

    private func resetApiKey() {
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: "OPENAI_API_KEY")
        alertMessage = "API 金鑰已重置"
        showAlert = true
    }
}