import SwiftUI
import os

/// 計時器協調器測試視圖
struct TimerTestView: View {
    // 狀態
    @State private var taskStatuses: [String: TimerCoordinator.TaskStatus] = [:]
    @State private var testResult: String = "尚未測試"
    @State private var testInProgress: Bool = false
    @State private var testStartTime: Date?
    
    // 動畫
    @State private var progressValue: Double = 0
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "TimerTest")
    
    // 時間格式化工具
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    var body: some View {
        List {
            Section(header: Text("計時器協調器測試")) {
                // 測試結果顯示
                VStack(alignment: .leading, spacing: 10) {
                    Text("測試結果:")
                        .font(.headline)
                    
                    Text(testResult)
                        .foregroundColor(getResultColor())
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 5)
                
                // 測試按鈕
                Button(action: {
                    runTimerCoordinatorTest()
                }) {
                    HStack {
                        Text(testInProgress ? "測試中..." : "測試計時器協調器")
                        if testInProgress {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                    }
                }
                .disabled(testInProgress)
                
                // 當測試進行中顯示進度
                if testInProgress {
                    ProgressView(value: progressValue, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            
            // 任務狀態部分
            if !taskStatuses.isEmpty {
                Section(header: Text("活動任務")) {
                    ForEach(Array(taskStatuses.keys.sorted()), id: \.self) { key in
                        if let status = taskStatuses[key] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(key)
                                        .font(.headline)
                                    
                                    Text("間隔: \(String(format: "%.1f", status.interval))秒")
                                        .font(.caption)
                                    
                                    if let lastExecution = status.lastExecution {
                                        Text("上次執行: \(timeFormatter.string(from: lastExecution))")
                                            .font(.caption)
                                    }
                                }
                                
                                Spacer()
                                
                                Text("\(status.executionCount)次")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("說明")) {
                Text("此測試會檢查所有活動的計時器任務是否正常運行。測試運行約15秒，將驗證各個計時器能否按照預定的時間間隔運行。")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("計時器測試")
    }
    
    // 根據測試結果決定顏色
    private func getResultColor() -> Color {
        if testResult.contains("成功") {
            return .green
        } else if testResult.contains("失敗") {
            return .red
        } else {
            return .primary
        }
    }
    
    // 執行計時器協調器測試
    private func runTimerCoordinatorTest() {
        // 設置測試狀態
        testInProgress = true
        testResult = "測試進行中..."
        testStartTime = Date()
        progressValue = 0.0
        
        // 取得最初的任務狀態
        refreshTaskStatus()
        
        // 添加測試任務
        setupTestTasks()
        
        // 定時更新進度
        let progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let startTime = testStartTime {
                let elapsedTime = Date().timeIntervalSince(startTime)
                progressValue = min(elapsedTime / 15.0, 1.0)
                refreshTaskStatus()
            }
        }
        
        // 15秒後結束測試
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            // 停止進度更新
            progressUpdateTimer.invalidate()
            
            // 分析測試結果
            analyzeTestResults()
            
            // 移除測試任務
            cleanupTestTasks()
            
            // 完成測試
            testInProgress = false
            progressValue = 1.0
        }
    }
    
    // 設置測試任務
    private func setupTestTasks() {
        // 添加用於測試的任務
        TimerCoordinator.shared.addTask(id: "test.1sec", interval: 1.0) {
            logger.debug("測試任務 1秒 執行")
        }
        
        TimerCoordinator.shared.addTask(id: "test.2sec", interval: 2.0) {
            logger.debug("測試任務 2秒 執行")
        }
        
        TimerCoordinator.shared.addTask(id: "test.5sec", interval: 5.0) {
            logger.debug("測試任務 5秒 執行")
        }
        
        // 確保TimerCoordinator正在運行
        if !TimerCoordinator.shared.isRunning {
            TimerCoordinator.shared.start()
        }
    }
    
    // 分析測試結果
    private func analyzeTestResults() {
        let statuses = TimerCoordinator.shared.getAllTaskStatus()
        var allTasksValid = true
        var failedTasks: [String] = []
        var resultMessage = ""
        
        for (id, status) in statuses {
            // 檢查各個測試任務的執行次數是否符合預期
            if id.starts(with: "test.") {
                let expectedExecutions: Int
                
                if id == "test.1sec" {
                    expectedExecutions = 14  // 預期執行14-15次 (15秒)
                } else if id == "test.2sec" {
                    expectedExecutions = 7   // 預期執行7-8次 (15秒)
                } else if id == "test.5sec" {
                    expectedExecutions = 3   // 預期執行3次 (15秒)
                } else {
                    continue  // 跳過其他非測試任務
                }
                
                // 允許1次誤差
                let minValid = expectedExecutions - 1
                let maxValid = expectedExecutions + 1
                
                if status.executionCount < minValid || status.executionCount > maxValid {
                    allTasksValid = false
                    failedTasks.append("\(id) (預期:\(expectedExecutions), 實際:\(status.executionCount))")
                }
            }
        }
        
        // 檢查常規任務是否也在運行
        let regularTasksRunning = statuses.keys.contains { id in
            return id.contains("heartRate") || id.contains("motion") || id.contains("sleepDetection")
        }
        
        // 生成結果消息
        if allTasksValid && regularTasksRunning {
            resultMessage = "測試成功! ✅\n所有計時器任務按預期執行。\n共檢測到 \(statuses.count) 個活動任務。"
        } else if !allTasksValid {
            resultMessage = "測試失敗! ❌\n以下任務執行次數不符合預期:\n" + failedTasks.joined(separator: "\n")
        } else {
            resultMessage = "測試部分成功。 ⚠️\n測試任務正常，但沒有檢測到任何系統計時器任務。"
        }
        
        testResult = resultMessage
    }
    
    // 清理測試任務
    private func cleanupTestTasks() {
        TimerCoordinator.shared.removeTask(id: "test.1sec")
        TimerCoordinator.shared.removeTask(id: "test.2sec")
        TimerCoordinator.shared.removeTask(id: "test.5sec")
    }
    
    // 刷新任務狀態
    private func refreshTaskStatus() {
        taskStatuses = TimerCoordinator.shared.getAllTaskStatus()
    }
} 