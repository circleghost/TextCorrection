import SwiftUI

struct PreferencesWindow: View {
    @AppStorage("OPENAI_API_KEY") private var apiKey: String = ""
    @State private var tempApiKey: String = ""
    @State private var showApiKeyInput: Bool = false

    var body: some View {
        VStack {
            // ... 現有代碼 ...

            if showApiKeyInput {
                TextField("輸入OpenAI API金鑰", text: $tempApiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("儲存API金鑰") {
                    apiKey = tempApiKey
                    showApiKeyInput = false
                }
                .padding()
            } else {
                Text("API金鑰: \(apiKey.isEmpty ? "未設置" : "已設置")")
                    .padding()

                Button("更改API金鑰") {
                    showApiKeyInput = true
                    tempApiKey = apiKey
                }
                .padding()
            }

            // ... 現有代碼 ...
        }
        .onAppear {
            showApiKeyInput = apiKey.isEmpty
        }
    }
}