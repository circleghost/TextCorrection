//
//  ContentView.swift
//  TextCorrection
//
//  Created by 李元魁 on 2024/9/7.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedText: String = ""
    @State private var showPopup: Bool = false
    @State private var showFloatingButton: Bool = false
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        ZStack {
            VStack {
                Text("請在任何應用程序中選擇文字")
                    .font(.headline)
                Text("當您選擇文字時，將會出現一個浮動按鈕")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            if showFloatingButton {
                FloatingButton(action: {
                    showPopup = true
                })
                .offset(x: 100 + dragOffset.width, y: 100 + dragOffset.height)  // 允許拖動
                .zIndex(1)  // 確保按鈕在最上層
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                )
            }

            if showPopup {
                PopupView(text: selectedText, isPresented: $showPopup)
            }
        }
        .frame(width: 300, height: 200)
        .onReceive(NotificationCenter.default.publisher(for: .didSelectText)) { notification in
            if let text = notification.userInfo?["selectedText"] as? String {
                self.selectedText = text
                self.showFloatingButton = true
            }
        }
    }
}

struct FloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "text.quote")
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(radius: 5)
        }
        .frame(width: 60, height: 60)
    }
}

struct PopupView: View {
    let text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("選取的文字：")
                .font(.headline)
            Text(text)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            Button("關閉") {
                isPresented = false
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(radius: 10)
        .frame(maxWidth: 300)
        .transition(.scale)
    }
}

#Preview {
    ContentView()
}
