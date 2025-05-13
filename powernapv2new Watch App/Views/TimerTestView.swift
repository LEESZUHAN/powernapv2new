import SwiftUI
import os

/// 計時器測試視圖
/// 用於測試和驗證計時器合併系統的正確運行
struct TimerTestView: View {
    @State private var isPending = false
    @State private var isRunningTest = false
    @State private var testProgress: Double = 0
    @State private var testResults: [String: Bool] = [:]
    @State private var testTasksAdded = false
    @State private var testDuration: TimeInterval = 10 // 默認10秒測試
    
    // 測試任務
    private let testTasks = [
        "test.task1": 1.0,    // 每1秒執行一次
        "test.task2": 2.0,    // 每2秒執行一次
        "test.task3": 3.0,    // 每3秒執行一次
        "test.task5": 5.0     // 每5秒執行一次
    ]
    
    // 記錄器
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "TimerTestView")
    
    // 用於更新測試進度的計時器
    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            Text("計時器系統測試")
                .font(.headline)
                .padding(.top)
            
            if isRunningTest {
                // 測試進行中顯示的內容
                VStack {
                    Text("正在測試中...")
                        .font(.body)
                    
                    // 進度條
                    ProgressView(value: testProgress)
                        .padding()
                    
                    Text("\(Int(testProgress * 100))%")
                        .font(.caption)
                    
                    Text("剩餘時間: \(formatRemainingTime())")
                        .font(.caption)
                }
                .onReceive(progressTimer) { _ in
                    if isRunningTest {
                        testProgress = TimerCoordinator.shared.getTestProgress()
                    }
                }
            } else if !testResults.isEmpty {
                // 顯示測試結果
                VStack {
                    Text("測試結果")
                        .font(.body)
                        .padding(.bottom, 5)
                    
                    // 結果摘要
                    let passedCount = testResults.values.filter { $0 }.count
                    let totalCount = testResults.count
                    
                    Text("通過: \(passedCount)/\(totalCount)")
                        .foregroundColor(passedCount == totalCount ? .green : .orange)
                        .padding(.bottom, 5)
                    
                    // 詳細結果列表
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(testResults.sorted(by: { $0.key < $1.key }), id: \.key) { task, passed in
                                HStack {
                                    Text(task)
                                        .font(.caption)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text(passed ? "通過" : "失敗")
                                        .font(.caption)
                                        .foregroundColor(passed ? .green : .red)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .frame(height: 100)
                }
            } else {
                // 還未運行測試時顯示的內容
                Text("選擇測試持續時間:")
                    .font(.body)
                    .padding(.top)
                
                Picker("測試時間", selection: $testDuration) {
                    Text("5秒").tag(5.0)
                    Text("10秒").tag(10.0)
                    Text("15秒").tag(15.0)
                    Text("30秒").tag(30.0)
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 100)
            }
            
            // 操作按鈕
            if isRunningTest {
                Button("取消測試") {
                    cancelTest()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding()
            } else {
                VStack {
                    Button("開始測試") {
                        startTest()
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .padding(.top)
                    
                    if !testResults.isEmpty {
                        Button("清除結果") {
                            testResults = [:]
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .padding(.top, 5)
                    }
                }
            }
        }
        .padding()
        .onDisappear {
            // 當視圖消失時清理任務
            cleanup()
        }
    }
    
    // 格式化剩餘時間
    private func formatRemainingTime() -> String {
        let remainingSeconds = testDuration * (1 - testProgress)
        return String(format: "%.1f秒", remainingSeconds)
    }
    
    // 開始測試
    private func startTest() {
        // 重置狀態
        testResults = [:]
        testProgress = 0
        isRunningTest = true
        
        logger.info("開始計時器系統測試，持續時間: \(testDuration)秒")
        
        // 添加測試任務
        addTestTasks()
        
        // 啟動測試
        TimerCoordinator.shared.startTimerTest(duration: testDuration) { results in
            // 測試完成後的回調
            DispatchQueue.main.async {
                self.testResults = results
                self.isRunningTest = false
                
                // 分析並記錄結果
                let passedCount = results.values.filter { $0 }.count
                let totalCount = results.count
                
                if passedCount == totalCount {
                    self.logger.info("測試全部通過！(\(passedCount)/\(totalCount))")
                } else {
                    self.logger.warning("部分測試失敗。通過: \(passedCount)/\(totalCount)")
                    
                    // 記錄失敗的任務
                    for (task, passed) in results {
                        if !passed {
                            self.logger.warning("任務失敗: \(task)")
                        }
                    }
                }
                
                // 移除測試任務
                removeTestTasks()
            }
        }
    }
    
    // 取消測試
    private func cancelTest() {
        logger.info("用戶取消了測試")
        isRunningTest = false
        
        // 移除測試任務
        removeTestTasks()
    }
    
    // 添加測試任務
    private func addTestTasks() {
        for (taskId, interval) in testTasks {
            TimerCoordinator.shared.addTask(id: taskId, interval: interval) {
                // 任務執行時的簡單操作
                self.logger.info("測試任務執行: \(taskId)")
            }
        }
        testTasksAdded = true
    }
    
    // 移除測試任務
    private func removeTestTasks() {
        if testTasksAdded {
            for taskId in testTasks.keys {
                TimerCoordinator.shared.removeTask(id: taskId)
            }
            testTasksAdded = false
        }
    }
    
    // 清理資源
    private func cleanup() {
        if isRunningTest {
            isRunningTest = false
        }
        
        removeTestTasks()
    }
}

// 預覽
struct TimerTestView_Previews: PreviewProvider {
    static var previews: some View {
        TimerTestView()
    }
} 