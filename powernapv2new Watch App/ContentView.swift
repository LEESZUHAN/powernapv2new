//
//  ContentView.swift
//  powernapv2new Watch App
//
//  Created by michaellee on 4/27/25.
//

import SwiftUI
import UserNotifications

// 導入PowerNapViewModel
@preconcurrency import Foundation

struct ContentView: View {
    @StateObject private var viewModel = PowerNapViewModel()
    
    // 使用枚舉跟踪UI狀態
    enum UIState {
        case preparing  // 準備狀態
        case monitoring // 監測狀態
        case countdown  // 倒計時狀態
    }
    
    // 定義反饋階段
    enum FeedbackStage {
        case initial       // 初始問題
        case suggestion    // 建議調整
        case thanks        // 感謝頁面
    }
    
    // 增加用於分頁控制的狀態
    @State private var selectedTab = 0
    
    // 增加用於查看日誌的狀態
    @State private var logFiles: [URL] = []
    @State private var selectedLogFile: URL?
    @State private var logContent: String = ""
    
    // 增加用於設置頁面的狀態
    @State private var thresholdOffset: Double = 0.0
    @State private var sleepSensitivity: Double = 0.5
    @State private var selectedAgeGroup: AgeGroup?
    
    // 新增：跟踪取消確認狀態
    @State private var showingCancelConfirmation: Bool = false
    
    // 新增：跟踪反饋階段
    @State private var feedbackStage: FeedbackStage = .initial
    @State private var feedbackWasAccurate: Bool = true
    
    // 根據ViewModel狀態計算UI狀態
    private var uiState: UIState {
        if !viewModel.isNapping {
            return .preparing
        } else if viewModel.sleepPhase == .awake || viewModel.sleepPhase == .falling {
            return .monitoring
        } else {
            return .countdown
        }
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // 主頁面
                ZStack {
                    // 背景色
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    // 根據UI狀態顯示不同內容
                    switch uiState {
                    case .preparing:
                        preparingView
                    case .monitoring:
                        monitoringView
                    case .countdown:
                        countdownView
                    }
                }
                .tag(0)
                
                // 測試功能頁面
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    testFunctionsView
                }
                .tag(1)
                
                // 數據記錄頁面
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    dataLogsView
                }
                .tag(2)
                
                // 新增：設置頁面
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    settingsView
                }
                .tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            // 使用背景隱藏視圖來觸發PreferenceKey，避免ScrollView contentOffset警告
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: TabViewHeightPreference.self, value: geometry.size.height)
                }
            )
            // 使用onPreferenceChange代替onAppear以避免每次頁面切換都重新加載
            .onPreferenceChange(TabViewHeightPreference.self) { _ in 
                // 只在首次加載時執行
                if logFiles.isEmpty {
                    loadLogFiles()
                }
                
                // 從ViewModel加載設置值
                if thresholdOffset == 0.0 && sleepSensitivity == 0.5 {
                    thresholdOffset = viewModel.userHRThresholdOffset
                    sleepSensitivity = viewModel.sleepSensitivity
                    selectedAgeGroup = viewModel.userSelectedAgeGroup
                }
            }
            
            // 反饋提示覆蓋層
            if viewModel.showingFeedbackPrompt {
                feedbackPromptView
            }
            
            // 新增：鬧鈴關閉UI覆蓋層
            if viewModel.showAlarmDismissUI {
                alarmDismissView
            }
        }
    }
    
    // 準備狀態視圖 - 使用官方推薦的WatchOS Picker實現
    private var preparingView: some View {
        VStack(spacing: 15) {
            Text("休息時間")
                .font(.headline)
                .foregroundColor(.gray)
            
            // 恢復為明確的wheel樣式Picker
            Picker(selection: $viewModel.napMinutes, label: Text("分鐘數")) {
                ForEach(1...30, id: \.self) { minutes in
                    Text("\(minutes)").tag(minutes)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(height: 100)
            
            Text("分鐘")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
            
            // 開始按鈕
            Button(action: {
                // 轉換為秒
                viewModel.napDuration = Double(viewModel.napMinutes) * 60
                viewModel.startNap()
            }) {
                Text("開始休息")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .cornerRadius(22)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal)
        }
        .padding()
    }
    
    // 測試功能頁面視圖 - 增加顯示心率、靜止心率和運動狀況
    private var testFunctionsView: some View {
        VStack {
            Text("開發測試功能")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .padding(.top, 5)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // 心率資訊區塊
                    VStack(spacing: 10) {
                        HStack {
                            Text("心率:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(viewModel.currentHeartRate))")
                                .foregroundColor(.green)
                                .font(.system(size: 18, weight: .bold))
                            Text("BPM")
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                        
                        HStack {
                            Text("靜止心率:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(viewModel.restingHeartRate))")
                                .foregroundColor(.orange)
                                .font(.system(size: 18, weight: .bold))
                            Text("BPM")
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                        
                        HStack {
                            Text("閾值:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(viewModel.heartRateThreshold))")
                                .foregroundColor(.purple)
                                .font(.system(size: 18, weight: .bold))
                            Text("BPM")
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                        
                        Divider()
                            .background(Color.gray)
                            .padding(.vertical, 5)
                        
                        HStack {
                            Text("運動強度:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.4f", viewModel.currentAcceleration))
                                .foregroundColor(viewModel.currentAcceleration > viewModel.motionThreshold ? .red : .green)
                                .font(.system(size: 18, weight: .bold))
                        }
                        
                        HStack {
                            Text("運動閾值:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.3f", viewModel.motionThreshold))
                                .foregroundColor(.blue)
                                .font(.system(size: 18, weight: .bold))
                        }
                        
                        HStack {
                            Text("運動狀態:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(viewModel.isResting ? "靜止" : "活動中")
                                .foregroundColor(viewModel.isResting ? .green : .red)
                                .font(.system(size: 18, weight: .bold))
                        }
                        
                        HStack {
                            Text("睡眠狀態:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(viewModel.isProbablySleeping ? "可能睡眠中" : "清醒")
                                .foregroundColor(viewModel.isProbablySleeping ? .blue : .yellow)
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    Spacer().frame(height: 10)
                    
                    Button(action: {
                        // 直接調用通知管理器發送通知
                        NotificationManager.shared.sendWakeupNotification()
                    }) {
                        Text("測試鬧鈴功能")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.orange)
                            .cornerRadius(25)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    
                    // 新增：測試反饋提示按鈕
                    Button(action: {
                        // 重置反饋狀態
                        feedbackStage = .initial
                        // 直接顯示反饋提示
                        viewModel.showingFeedbackPrompt = true
                        
                        // 設置10秒自動消失
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            if viewModel.showingFeedbackPrompt {
                                viewModel.showingFeedbackPrompt = false
                                feedbackStage = .initial
                            }
                        }
                    }) {
                        Text("測試反饋提示")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.purple)
                            .cornerRadius(25)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // 添加情境測試區域標題
                    Text("情境測試區")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                    
                    // 情境1：用戶入睡，系統正確檢測到
                    Button(action: {
                        feedbackStage = .initial
                        viewModel.simulateScenario1Feedback()
                    }) {
                        Text("情境1：正確檢測睡眠")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.green)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
                    
                    // 情境2：用戶入睡，系統未檢測到
                    Button(action: {
                        feedbackStage = .initial
                        viewModel.simulateScenario2Feedback()
                    }) {
                        Text("情境2：未檢測到睡眠")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.blue)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
                    
                    // 情境3：用戶未入睡，系統誤判為睡眠
                    Button(action: {
                        feedbackStage = .initial
                        viewModel.simulateScenario3Feedback()
                    }) {
                        Text("情境3：誤判為睡眠")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.red)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
                    
                    // 情境4：用戶未入睡，系統正確未檢測
                    Button(action: {
                        feedbackStage = .initial
                        viewModel.simulateScenario4Feedback()
                    }) {
                        Text("情境4：正確未檢測")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.orange)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
                    
                    // 新增：測試鬧鈴喚醒流程
                    Button(action: {
                        // 觸發整個喚醒流程
                        viewModel.isAlarmSounding = true
                        viewModel.showAlarmDismissUI = true
                        
                        // 啟動鬧鈴通知和震動
                        NotificationManager.shared.sendWakeupNotification()
                    }) {
                        Text("測試鬧鈴喚醒流程")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 5)
    }
    
    // 監測狀態視圖
    private var monitoringView: some View {
        VStack {
            Spacer().frame(height: 20)
            
            Text("監測中")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white)
                .padding(.bottom, 10)
            
            Spacer()
            
            // 等待文字 - 接近置中
            Text("等待入睡...")
                .font(.system(size: 22))
                .foregroundColor(.gray)
            
            Spacer()
            
            // 取消按鈕區域 - 加入確認機制
            if showingCancelConfirmation {
                // 顯示確認按鈕
                Button(action: {
                    // 確認取消
                    viewModel.stopNap()
                    showingCancelConfirmation = false
                }) {
                    Text("確認取消")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 160, height: 44)
                        .background(Color.red)
                        .cornerRadius(22)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 10)
                
                // 添加返回選項
                Button(action: {
                    // 取消確認狀態
                    showingCancelConfirmation = false
                }) {
                    Text("繼續監測")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 30)
            } else {
                // 顯示第一次取消按鈕
                Button(action: {
                    // 顯示確認按鈕
                    showingCancelConfirmation = true
                    
                    // 5秒後自動取消確認狀態
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        showingCancelConfirmation = false
                    }
                }) {
                    Text("取消")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 44)
                        .background(Color.red)
                        .cornerRadius(22)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 30)
            }
        }
        .padding()
    }
    
    // 倒計時狀態視圖
    private var countdownView: some View {
        VStack(spacing: 30) {
            // 大倒計時
            Text(timeString(from: viewModel.remainingTime))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            // 睡眠階段指示器
            Text(sleepPhaseText)
                .font(.system(size: 18))
                .foregroundColor(.gray)
            
            Spacer()
            
            // 取消按鈕
            Button(action: {
                viewModel.stopNap()
            }) {
                Text("取消")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 120, height: 44)
                    .background(Color.red)
                    .cornerRadius(22)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 20)
        }
        .padding()
    }
    
    // 數據記錄頁面
    private var dataLogsView: some View {
        VStack {
            if selectedLogFile == nil {
                // 顯示日誌文件列表
                logFilesListView
            } else {
                // 顯示選定日誌的內容
                logDetailView
            }
        }
    }
    
    // 日誌文件列表視圖
    private var logFilesListView: some View {
        VStack {
            Text("睡眠數據記錄")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 5)
                .padding(.top, 5)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if logFiles.isEmpty {
                        Text("尚無記錄")
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    } else {
                        ForEach(logFiles, id: \.lastPathComponent) { fileURL in
                            Button(action: {
                                selectedLogFile = fileURL
                                loadLogContent(from: fileURL)
                            }) {
                                HStack {
                                    Text(formatLogFilename(fileURL.lastPathComponent))
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 12))
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 15)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Button(action: loadLogFiles) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重新整理")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .padding(.top, 15)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
            }
        }
    }
    
    // 日誌詳細視圖
    private var logDetailView: some View {
        VStack {
            HStack {
                Button(action: {
                    selectedLogFile = nil
                    logContent = ""
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                if let fileName = selectedLogFile?.lastPathComponent {
                    Text(formatLogFilename(fileName))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal)
            .padding(.top, 5)
            .padding(.bottom, 5)
            
            ScrollView(.vertical, showsIndicators: false) {
                if logContent.isEmpty {
                    Text("載入中...")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    Text(formatLogSummary(logContent))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
    }
    
    // 加載日誌文件列表
    private func loadLogFiles() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let logDirectory = documentsDirectory.appendingPathComponent("LogFiles")
        
        do {
            // 檢查目錄是否存在
            if fileManager.fileExists(atPath: logDirectory.path) {
                // 獲取所有.csv文件
                let fileURLs = try fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
                logFiles = fileURLs
                    .filter { $0.pathExtension == "csv" }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent } // 按名稱逆序排列
            } else {
                logFiles = []
            }
        } catch {
            print("讀取日誌文件失敗: \(error.localizedDescription)")
            logFiles = []
        }
    }
    
    // 加載日誌內容
    private func loadLogContent(from fileURL: URL) {
        do {
            logContent = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            logContent = "無法讀取文件: \(error.localizedDescription)"
        }
    }
    
    // 格式化日誌摘要
    private func formatLogSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        
        // 檢查是否為空
        if lines.isEmpty {
            return "空白記錄"
        }
        
        // 獲取頭部和總結部分
        let header = lines.first ?? ""
        var summary = ""
        var lastEntries = ""
        
        // 查找總結段落
        if let summaryStart = lines.firstIndex(where: { $0.contains("--- 會話結束 ---") }) {
            summary = lines[summaryStart...].joined(separator: "\n")
        }
        
        // 獲取最後5條數據記錄
        let dataLines = lines.filter { $0.contains(",") && !$0.contains("Timestamp") }
        if dataLines.count > 0 {
            let lastDataLines = Array(dataLines.suffix(min(5, dataLines.count)))
            lastEntries = "\n\n最後記錄的數據:\n" + lastDataLines.map { formatDataLine($0) }.joined(separator: "\n")
        }
        
        // 計算基本統計信息
        var statsText = ""
        if dataLines.count > 0 {
            let hrValues = dataLines.compactMap { line -> Double? in
                let components = line.components(separatedBy: ",")
                return components.count > 1 ? Double(components[1]) : nil
            }
            
            if !hrValues.isEmpty {
                let avgHR = hrValues.reduce(0, +) / Double(hrValues.count)
                let minHR = hrValues.min() ?? 0
                let maxHR = hrValues.max() ?? 0
                
                statsText = """
                
                記錄點數: \(dataLines.count)
                平均心率: \(Int(avgHR)) BPM
                最低心率: \(Int(minHR)) BPM
                最高心率: \(Int(maxHR)) BPM
                """
            }
        }
        
        return "\(header)\n\(statsText)\n\(lastEntries)\n\n\(summary)"
    }
    
    // 格式化數據行
    private func formatDataLine(_ line: String) -> String {
        let components = line.components(separatedBy: ",")
        if components.count < 9 {
            return line // 返回原始行
        }
        
        // 提取關鍵數據
        let timestamp = components[0]
        let hr = components[1]
        let sleepPhase = components[8]
        
        return "[\(timestamp)] HR: \(hr) - \(sleepPhase)"
    }
    
    // 將秒數轉換為時間字符串
    private func timeString(from seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 獲取當前睡眠階段的描述文本
    private var sleepPhaseText: String {
        switch viewModel.sleepPhase {
        case .awake:
            return "清醒狀態"
        case .falling:
            return "即將入睡"
        case .light:
            return "輕度睡眠"
        case .deep:
            return "深度睡眠"
        case .rem:
            return "REM睡眠"
        }
    }
    
    // 新增：設置頁面
    private var settingsView: some View {
        VStack {
            Text("睡眠設置")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 25) {
                    // 使用拆分後的子視圖組件
                    ThresholdAdjustmentView(viewModel: viewModel)
                    SensitivitySettingView(viewModel: viewModel, sleepSensitivity: $sleepSensitivity)
                    AgeGroupSettingView(viewModel: viewModel, selectedAgeGroup: $selectedAgeGroup)
                    HeartRateInfoView(viewModel: viewModel)
                    ResetSettingsButton(viewModel: viewModel, thresholdOffset: $thresholdOffset, sleepSensitivity: $sleepSensitivity)
                }
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
    }
    
    // 格式化日誌文件名
    private func formatLogFilename(_ filename: String) -> String {
        return filename
            .replacingOccurrences(of: "powernap_session_", with: "")
            .replacingOccurrences(of: ".csv", with: "")
    }
    
    // 添加反饋提示視圖
    private var feedbackPromptView: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 15) {
                // 根據不同階段顯示不同內容
                Group {
                    switch feedbackStage {
                    case .initial:
                        // 初始反饋問題內容
                        initialFeedbackView
                    
                    case .suggestion:
                        // 建議調整頁面
                        suggestionFeedbackView
                    
                    case .thanks:
                        // 感謝頁面
                        thanksFeedbackView
                    }
                }
            }
        }
        .padding()
        .background(Color.black)
        .cornerRadius(15)
        .shadow(radius: 10)
    }
    
    // 初始反饋問題視圖
    private var initialFeedbackView: some View {
        VStack {
            Text("睡眠檢測準確嗎？")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            HStack(spacing: 20) {
                // 準確按鈕
                Button(action: {
                    feedbackWasAccurate = true
                    feedbackStage = .thanks
                    
                    // 處理反饋
                    viewModel.processFeedback(wasAccurate: true)
                    
                    // 3秒後關閉
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        viewModel.showingFeedbackPrompt = false
                        feedbackStage = .initial // 重置狀態
                    }
                }) {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                        Text("準確")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                
                // 不準確按鈕
                Button(action: {
                    feedbackWasAccurate = false
                    feedbackStage = .suggestion
                    
                    // 處理反饋
                    viewModel.processFeedback(wasAccurate: false)
                }) {
                    VStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                        Text("不準確")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 15)
            
            // 關閉按鈕
            Button(action: {
                viewModel.showingFeedbackPrompt = false
                feedbackStage = .initial // 重置狀態
            }) {
                Text("暫不評價")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 10)
        }
    }
    
    // 建議調整頁面視圖
    private var suggestionFeedbackView: some View {
        VStack {
            Text("需要調整檢測靈敏度？")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            // 根據當前情境提供不同建議
            if viewModel.lastFeedbackType == .falsePositive {
                // 情境3: 用戶未入睡但系統誤判為睡眠
                Text("系統似乎過於寬鬆地判定您入睡了。您可以到設置頁面點擊「判定嚴謹」按鈕來降低閾值")
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // 展示按鈕圖示作為視覺輔助
                HStack {
                    Image(systemName: "arrow.left.circle.fill")
                        .foregroundColor(.red)
                    
                    Text("判定嚴謹")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding(.vertical, 10)
            } else {
                // 情境2: 用戶入睡但系統未檢測到
                Text("系統似乎無法檢測到您已入睡。您可以到設置頁面點擊「判定寬鬆」按鈕來增加閾值")
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // 展示按鈕圖示作為視覺輔助
                HStack {
                    Image(systemName: "arrow.left.circle.fill")
                        .foregroundColor(.blue)
                    
                    Text("判定寬鬆")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding(.vertical, 10)
            }
            
            // 前往設置按鈕
            Button(action: {
                viewModel.showingFeedbackPrompt = false
                feedbackStage = .initial
                selectedTab = 3 // 切換到設置頁面 (第4個標籤)
            }) {
                Text("前往設置")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
            
            // 關閉按鈕
            Button(action: {
                viewModel.showingFeedbackPrompt = false
                feedbackStage = .initial
            }) {
                Text("稍後再說")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 10)
        }
    }
    
    // 感謝頁面視圖
    private var thanksFeedbackView: some View {
        VStack(spacing: 15) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundColor(.pink)
                .padding(.top, 10)
            
            Text("感謝您的反饋！")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(feedbackWasAccurate ? "我們將繼續優化睡眠檢測" : "您的反饋已記錄")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
    
    // 新增：鬧鈴關閉UI覆蓋層
    private var alarmDismissView: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // 鬧鈴圖標
                Image(systemName: "alarm.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                    .padding(.bottom, 10)
                
                Text("小睡結束")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("是時候起來了！")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
                
                // 單個大型按鈕，簡單明了
                Button(action: {
                    viewModel.dismissAlarm()
                }) {
                    Text("關閉鬧鈴")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 20)
            }
            .padding(25)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
            .padding(.horizontal, 15)
        }
    }
}

// 自定義PreferenceKey用於避免不必要的更新
struct TabViewHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 心率閾值調整視圖
struct ThresholdAdjustmentView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("心率閾值調整")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("調整睡眠檢測的閾值標準")
                .font(.caption)
                .foregroundColor(.gray)
            
            // 顯示當前設置
            HStack {
                Text("當前閾值:")
                    .foregroundColor(.gray)
                Spacer()
                Text("RHR的\(Int((0.9 + viewModel.userHRThresholdOffset) * 100))%")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
            }
            .padding(.top, 5)
            
            // 確認機制
            if viewModel.showingThresholdConfirmation {
                Button(action: {
                    // 確認閾值調整
                    let newValue = viewModel.pendingThresholdOffset ?? (viewModel.userHRThresholdOffset + 0.05)
                    viewModel.setUserHeartRateThresholdOffset(newValue)
                    viewModel.showingThresholdConfirmation = false
                    viewModel.pendingThresholdOffset = nil
                }) {
                    Text("確認調整閾值")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 5)
                
                Button(action: {
                    // 取消確認
                    viewModel.showingThresholdConfirmation = false
                    viewModel.pendingThresholdOffset = nil
                }) {
                    Text("取消")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.5))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 5)
            } else {
                // 雙按鈕佈局
                HStack(spacing: 10) {
                    // 判定嚴謹按鈕 - 降低閾值
                    Button(action: {
                        // 設置待確認的閾值調整為降低5%
                        viewModel.pendingThresholdOffset = viewModel.userHRThresholdOffset - 0.05
                        viewModel.showingThresholdConfirmation = true
                        
                        // 5秒後自動取消確認狀態
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if viewModel.showingThresholdConfirmation {
                                viewModel.showingThresholdConfirmation = false
                                viewModel.pendingThresholdOffset = nil
                            }
                        }
                    }) {
                        Text("判定嚴謹")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 判定寬鬆按鈕 - 增加閾值
                    Button(action: {
                        // 設置待確認的閾值調整為增加5%
                        viewModel.pendingThresholdOffset = viewModel.userHRThresholdOffset + 0.05
                        viewModel.showingThresholdConfirmation = true
                        
                        // 5秒後自動取消確認狀態
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if viewModel.showingThresholdConfirmation {
                                viewModel.showingThresholdConfirmation = false
                                viewModel.pendingThresholdOffset = nil
                            }
                        }
                    }) {
                        Text("判定寬鬆")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 5)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

/// 睡眠檢測敏感度視圖
struct SensitivitySettingView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    @Binding var sleepSensitivity: Double
    
    // 計算調整值：從-5%到+5%（修改為直覺一致的計算方式）
    private var adjustmentValue: Int {
        // 新公式：讓sleepSensitivity從0.0到1.0對應-5%到+5%
        let adjustment = (viewModel.sleepSensitivity * 10) - 5
        return Int(adjustment)
    }
    
    // 生成顯示文字，包含正負號
    private var adjustmentDisplay: String {
        if adjustmentValue > 0 {
            return "+\(adjustmentValue)%"
        } else if adjustmentValue < 0 {
            return "\(adjustmentValue)%"
        } else {
            return "0%"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("睡眠檢測敏感度")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("調整檢測睡眠的靈敏度")
                .font(.caption)
                .foregroundColor(.gray)
            
            // 使用按鈕代替Slider
            HStack {
                Button(action: {
                    let newValue = max(viewModel.sleepSensitivity - 0.1, 0.0)
                    viewModel.setSleepSensitivity(newValue)
                    sleepSensitivity = newValue
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // 修改顯示格式：從百分比改為調整值
                Text(adjustmentDisplay)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    let newValue = min(viewModel.sleepSensitivity + 0.1, 1.0)
                    viewModel.setSleepSensitivity(newValue)
                    sleepSensitivity = newValue
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 5)
            
            HStack {
                Text("嚴謹")
                    .font(.caption2)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("寬鬆")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

/// 年齡組設置視圖
struct AgeGroupSettingView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    @Binding var selectedAgeGroup: AgeGroup?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("年齡組設置")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("選擇您的年齡組以優化檢測參數")
                .font(.caption)
                .foregroundColor(.gray)
            
            // 按鈕組佈局
            HStack(spacing: 8) {
                ageGroupButton(title: "青少年", ageGroup: .teen)
                ageGroupButton(title: "成人", ageGroup: .adult)
                ageGroupButton(title: "銀髮族", ageGroup: .senior)
            }
            .padding(.top, 5)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private func ageGroupButton(title: String, ageGroup: AgeGroup) -> some View {
        Button(action: {
            selectedAgeGroup = ageGroup
            viewModel.setUserAgeGroup(ageGroup)
        }) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    selectedAgeGroup == ageGroup 
                    ? Color.blue 
                    : Color.gray.opacity(0.5)
                )
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 心率信息視圖
struct HeartRateInfoView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("當前心率信息")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                Text("靜息心率:")
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(viewModel.restingHeartRate))")
                    .foregroundColor(.orange)
                    .font(.system(size: 18, weight: .bold))
                Text("BPM")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
            
            HStack {
                Text("睡眠閾值:")
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(viewModel.heartRateThreshold))")
                    .foregroundColor(.blue)
                    .font(.system(size: 18, weight: .bold))
                Text("BPM")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
            
            // 自動優化信息
            if let currentUserProfile = viewModel.currentUserProfile,
               let lastUpdate = currentUserProfile.lastModelUpdateDate {
                Divider()
                    .background(Color.gray.opacity(0.5))
                    .padding(.vertical, 5)
                
                HStack {
                    Text("自動優化:")
                        .foregroundColor(.gray)
                    Spacer()
                    
                    Text("已啟用")
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .medium))
                }
                
                HStack {
                    Text("最近優化:")
                        .foregroundColor(.gray)
                    Spacer()
                    
                    // 格式化日期為「MM/dd」格式
                    let formattedDate: String = {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "MM/dd"
                        return dateFormatter.string(from: lastUpdate)
                    }()
                    
                    Text(formattedDate)
                        .foregroundColor(.white)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
        .allowsHitTesting(false)
        .focusable(false)
    }
}

/// 重設按鈕
struct ResetSettingsButton: View {
    @ObservedObject var viewModel: PowerNapViewModel
    @Binding var thresholdOffset: Double
    @Binding var sleepSensitivity: Double
    
    var body: some View {
        Button(action: {
            // 重置設置
            thresholdOffset = 0.0
            sleepSensitivity = 0.5
            viewModel.setUserHeartRateThresholdOffset(0.0)
            viewModel.setSleepSensitivity(0.5)
        }) {
            Text("重設為默認設置")
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

#Preview {
    ContentView()
}
