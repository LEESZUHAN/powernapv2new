import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    @State private var showTimerTest = false
    @State private var timerTestResults: [String: String] = [:]
    
    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 15) {
                    // 標題
                    Text("設定")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    
                    // 統一的列表項風格
                    VStack(spacing: 8) {
                        // 原有設置選項保持不變
                        // ...
                        
                        // 計時器測試按鈕
                        Button {
                            showTimerTest = true
                            runTimerTest()
                        } label: {
                            settingRow(
                                icon: "timer",
                                title: "計時器系統測試",
                                iconColor: .green
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showTimerTest) {
                            TimerTestView(results: timerTestResults)
                        }
                    }
                    .padding(.horizontal)
                    
                    // 計時器測試說明
                    VStack(alignment: .leading, spacing: 8) {
                        Text("計時器系統優化")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.bottom, 4)
                        
                        Text("應用已使用合併計時器系統優化，將原本多個獨立計時器合併為統一管理，大幅提升電池續航和系統性能。")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)
                    }
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
            .background(Color.black)
        }
    }
    
    // 執行計時器測試
    private func runTimerTest() {
        // 執行計時器測試
        timerTestResults = TimerCoordinator.shared.runTaskTest()
        
        // 如果沒有任何任務，添加提示信息
        if timerTestResults.isEmpty {
            timerTestResults["status"] = "系統中沒有註冊的計時器任務"
        }
        
        // 添加總體任務數量信息
        let taskCount = TimerCoordinator.shared.getTaskCount()
        timerTestResults["task_count"] = "總計時器任務數量: \(taskCount)"
    }
    
    // 設置行項目通用視圖
    private func settingRow(icon: String, title: String, iconColor: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
            
            Text(title)
                .foregroundColor(.white)
                .font(.system(size: 16))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color(white: 0.18))
        .cornerRadius(10)
    }
}

// 計時器測試結果顯示視圖
struct TimerTestView: View {
    let results: [String: String]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("測試結果")) {
                    ForEach(results.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .fontWeight(.medium)
                            Spacer()
                            Text(value)
                                .foregroundColor(getResultColor(value))
                        }
                    }
                }
                
                Section(header: Text("說明")) {
                    Text("此測試檢查各計時器任務是否按預期間隔運行。正常情況下，所有任務的實際間隔應與設定值接近。")
                    Text("計時器合併優化將多個獨立計時器合併為單一調度系統，減少資源佔用並提高電池效率。")
                }
            }
            .navigationTitle("計時器系統測試")
            .toolbar {
                Button("關閉") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
    
    // 根據結果文本設置顏色
    private func getResultColor(_ result: String) -> Color {
        if result.contains("正常") {
            return .green
        } else if result.contains("等待中") {
            return .orange
        } else if result.contains("失敗") || result.contains("錯誤") || result.contains("異常") {
            return .red
        } else {
            return .primary
        }
    }
} 