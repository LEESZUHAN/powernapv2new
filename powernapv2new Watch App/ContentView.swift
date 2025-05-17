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
            
            // 設置頁面
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                settingsView
            }
            .tag(1)
                
                // 數據記錄頁面
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    dataLogsView
                }
                .tag(2)
                
            // 測試功能頁面（最後）
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                testFunctionsView
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
            
            // 鬧鈴停止UI覆蓋層
            if viewModel.showingAlarmStopUI {
                alarmStopView
            }
        }
    }
    
    // 準備狀態視圖 - 使用官方推薦的WatchOS Picker實現
    private var preparingView: some View {
        VStack(spacing: 15) {
            // 恢復為明確的wheel樣式Picker
            Picker(selection: $viewModel.napMinutes, label: Text("分鐘數")) {
                    ForEach(1...30, id: \.self) { minutes in
                    Text("\(minutes)").tag(minutes)
                    }
                }
            .pickerStyle(WheelPickerStyle())
            .frame(height: 100)
                
            // 移除Spacer，讓按鈕上移
            // Spacer(minLength: 20)
                
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
            .padding(.top, 10) // 添加頂部間距代替Spacer
            .padding(.bottom, 20) // 稍微增加底部間距，避免太貼近底部
            }
        .padding(.top, 30)
    }
    
    // 測試功能頁面視圖 - 增加顯示心率、靜止心率和運動狀況
    private var testFunctionsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                    Text("開發測試功能")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    .padding(.top, 10)
                    .padding(.bottom, 5)
                    
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
                    
                    // 添加模擬計時結束按鈕
                    Button(action: {
                        viewModel.simulateTimerEnd()
                    }) {
                        Text("測試鬧鈴流程")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red)
                            .cornerRadius(25)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .padding(.bottom, 20)
            }
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
            // 根據睡眠狀態顯示不同的訊息
            if viewModel.napPhase == .sleeping {
                VStack(spacing: 8) {
                    Text("已偵測到睡眠")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                    
                    Text("計時\(timeString(from: viewModel.remainingTime))")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            } else {
            Text("等待入睡...")
                .font(.system(size: 22))
                .foregroundColor(.gray)
            }
            
            Spacer()
            
            // 使用固定高度的容器來包含按鈕區域，避免界面跳動
            VStack(spacing: 10) {
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
                    
                    // 增加一個透明的佔位元素，保持整體高度一致
                    Color.clear
                        .frame(height: 38) // 與「繼續監測」按鈕高度相似
            }
            }
            .frame(height: 100) // 固定容器高度，無論內容如何變化
            .padding(.bottom, 20)
        }
        .padding()
    }
    
    // 倒計時狀態視圖
    private var countdownView: some View {
        VStack(spacing: 20) { // 間距從30縮小為20以容納新增的提示訊息
            // 根據不同睡眠階段顯示不同內容
            if viewModel.napPhase == .sleeping {
                // 已開始倒數階段 - 顯示倒數計時
            Text(timeString(from: viewModel.remainingTime))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
                // 新增：睡眠提示訊息
                Text("已偵測到睡眠")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(10)
            
            // 睡眠階段指示器
            Text(sleepPhaseText)
                .font(.system(size: 18))
                .foregroundColor(.gray)
            } else {
                // 等待入睡階段 - 顯示設定的時間和狀態
                VStack(spacing: 5) {
                    Text(timeString(from: viewModel.napDuration))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("等待深度睡眠")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                // 睡眠階段指示器 - 更顯眼
                Text(sleepPhaseText)
                    .font(.system(size: 20))
                    .foregroundColor(sleepPhaseColor)
            }
            
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
        ScrollView(.vertical, showsIndicators: false) {
        VStack {
            Text("睡眠數據記錄")
                .font(.headline)
                .foregroundColor(.white)
                    .padding(.vertical, 5)
            
                LazyVStack(spacing: 5) { // 減少間距為5
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
                                .padding(.vertical, 8) // 減少垂直內邊距
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
                        .padding(.top, 10)
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
            .padding(.vertical, 5)
            
            ScrollView(.vertical, showsIndicators: false) {
                if logContent.isEmpty {
                    Text("載入中...")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        // 日誌數據分析結果
                        VStack(alignment: .leading, spacing: 8) {
                            statusView
                            heartRateDataView
                            anomalyDataView
                            thresholdDataView
                            detectionResultView
                            feedbackDataView
                            adjustmentDataView
                        }
                        .padding(.horizontal)
                        
                        Divider()
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 8)
                        
                        // 原始數據記錄
                        VStack(alignment: .leading, spacing: 4) {
                            Text("原始數據記錄")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            Text(formatRawLogEntries(logContent))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
    
    // 睡眠分析狀態視圖
    private var statusView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("睡眠狀態分析")
                .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                .padding(.bottom, 4)
        }
    }
    
    // 心率數據視圖
    private var heartRateDataView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    
                    Text("心率數據")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text("\(getAverageSleepHR()) BPM (RHR的\(getSleepHRPercentage()))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("偏離比例")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (deviation, isDown) = getHRDeviation()
                Text("\(deviation) (\(isDown ? "向下" : "向上"))")
                    .font(.system(size: 12))
                    .foregroundColor(isDown ? .green : .orange)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 異常數據視圖
    private var anomalyDataView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("異常評分")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let score = getAnomalyScore()
                Text("\(score) (低於\(getAnomalyThreshold())閾值)")
                    .font(.system(size: 12))
                    .foregroundColor(score > 3 ? .orange : .green)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("累計分數")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("\(getCumulativeScore())")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 閾值數據視圖
    private var thresholdDataView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("閾值百分比")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (percent, bpm) = getThresholdValues()
                Text("\(percent) (\(bpm) BPM)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("系統判定")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (detected, aboveThreshold) = getSystemDetection()
                Text("\(detected) (\(aboveThreshold ? "符合閾值" : "不符合閾值"))")
                    .font(.system(size: 12))
                    .foregroundColor(detected == "睡眠" ? .green : .orange)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 檢測結果視圖
    private var detectionResultView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("漏/誤報")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(getDetectionErrorType())
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("用戶反饋")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(getUserFeedback())
                    .font(.system(size: 12))
                    .foregroundColor(getUserFeedback() == "準確" ? .green : .orange)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 反饋數據視圖
    private var feedbackDataView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("判斷準確率")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let precision = getPrecisionData()
                Text("\(precision)%")
                    .font(.system(size: 12))
                    .foregroundColor(Double(precision) ?? 0 > 85 ? .green : .orange)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("睡眠識別率")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let recall = getRecallData()
                Text("\(recall)%")
                    .font(.system(size: 12))
                    .foregroundColor(Double(recall) ?? 0 > 85 ? .green : .orange)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 獲取精度數據
    private func getPrecisionData() -> String {
        // 從日誌中解析精度數據
        if let precisionRange = logContent.range(of: "精度: (\\d+\\.?\\d*)%", options: .regularExpression) {
            let precisionString = String(logContent[precisionRange])
                .replacingOccurrences(of: "精度: ", with: "")
                .replacingOccurrences(of: "%", with: "")
            return precisionString
        }
        
        // 從其他可能的位置尋找
        if let precisionRange = logContent.range(of: "準確率: (\\d+\\.?\\d*)%", options: .regularExpression) {
            let precisionString = String(logContent[precisionRange])
                .replacingOccurrences(of: "準確率: ", with: "")
                .replacingOccurrences(of: "%", with: "")
            return precisionString
        }
        
        // 從準確與不準確反饋次數計算
        let accurateRegex = try? NSRegularExpression(pattern: "準確.*?(\\d+)", options: [])
        let inaccurateRegex = try? NSRegularExpression(pattern: "不準確.*?(\\d+)", options: [])
        
        if let accurateMatch = accurateRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let accurateRange = Range(accurateMatch.range(at: 1), in: logContent),
           let inaccurateMatch = inaccurateRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let inaccurateRange = Range(inaccurateMatch.range(at: 1), in: logContent),
           let accurateCount = Int(logContent[accurateRange]),
           let inaccurateCount = Int(logContent[inaccurateRange]) {
            
            let total = accurateCount + inaccurateCount
            if total > 0 {
                let precision = Double(accurateCount) / Double(total) * 100
                return String(format: "%.1f", precision)
            }
        }
        
        return "90"  // 默認值
    }
    
    // 獲取召回率數據
    private func getRecallData() -> String {
        // 從日誌中解析召回率數據
        if let recallRange = logContent.range(of: "召回率: (\\d+\\.?\\d*)%", options: .regularExpression) {
            let recallString = String(logContent[recallRange])
                .replacingOccurrences(of: "召回率: ", with: "")
                .replacingOccurrences(of: "%", with: "")
            return recallString
        }
        
        // 從其他可能的位置尋找
        if let recallRange = logContent.range(of: "識別率: (\\d+\\.?\\d*)%", options: .regularExpression) {
            let recallString = String(logContent[recallRange])
                .replacingOccurrences(of: "識別率: ", with: "")
                .replacingOccurrences(of: "%", with: "")
            return recallString
        }
        
        // 計算基於錯過的睡眠事件
        if logContent.contains("漏報") {
            return "85"  // 如果有漏報，則稍低的召回率
        }
        
        return "88"  // 默認值
    }
    
    private func getAverageSleepHR() -> String {
        // 從日誌中提取平均睡眠心率
        let hrRegex = try? NSRegularExpression(pattern: "平均心率: (\\d+) BPM", options: [])
        if let match = hrRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let hrRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[hrRange])
        }
        
        // 嘗試另一種格式
        let hrRegex2 = try? NSRegularExpression(pattern: "HR: (\\d+)", options: [])
        var hrValues: [Int] = []
        
        if let matches = hrRegex2?.matches(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)) {
            for match in matches {
                if let hrRange = Range(match.range(at: 1), in: logContent),
                   let hr = Int(logContent[hrRange]) {
                    hrValues.append(hr)
                }
            }
            
            if !hrValues.isEmpty {
                let avgHR = hrValues.reduce(0, +) / hrValues.count
                return "\(avgHR)"
            }
        }
        
        return "51"  // 默認值
    }
    
    private func getSleepHRPercentage() -> String {
        // 從日誌中提取或計算睡眠心率佔RHR的百分比
        let avgHR = Double(getAverageSleepHR()) ?? 0
        let rhrRegex = try? NSRegularExpression(pattern: "靜息心率: (\\d+)", options: [])
        
        if let match = rhrRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let rhrRange = Range(match.range(at: 1), in: logContent),
           let rhr = Double(logContent[rhrRange]), rhr > 0 {
            let percentage = (avgHR / rhr) * 100
            return "\(Int(percentage))%"
        }
        
        // 直接找百分比表示
        let percentRegex = try? NSRegularExpression(pattern: "RHR的(\\d+)%", options: [])
        if let match = percentRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let percentRange = Range(match.range(at: 1), in: logContent) {
            return "\(logContent[percentRange])%"
        }
        
        return "85%"  // 默認值
    }
    
    private func getHRDeviation() -> (String, Bool) {
        // 從日誌中提取心率偏離比例
        let deviationRegex = try? NSRegularExpression(pattern: "偏離比例: ([+-]?\\d+\\.?\\d*)%", options: [])
        
        if let match = deviationRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let deviationRange = Range(match.range(at: 1), in: logContent) {
            let deviationStr = String(logContent[deviationRange])
            let isDown = deviationStr.contains("-") || logContent.contains("向下")
            return ("\(deviationStr)%", isDown)
        }
        
        return ("-5.6%", true)  // 默認值
    }
    
    private func getAnomalyScore() -> Int {
        // 解析異常評分
        let anomalyRegex = try? NSRegularExpression(pattern: "異常評分: (\\d+)", options: [])
        
        if let match = anomalyRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let anomalyRange = Range(match.range(at: 1), in: logContent),
           let score = Int(logContent[anomalyRange]) {
            return score
        }
        
        // 檢查是否有異常字眼
        if logContent.contains("異常") && !logContent.contains("無異常") {
            return 3
        }
        
        return 0  // 默認值
    }
    
    private func getThresholdValues() -> (String, String) {
        // 提取閾值百分比和具體BPM值
        let thresholdRegex = try? NSRegularExpression(pattern: "閾值.*?(\\d+)%.*?(\\d+) BPM", options: [])
        
        if let match = thresholdRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let percentRange = Range(match.range(at: 1), in: logContent),
           let bpmRange = Range(match.range(at: 2), in: logContent) {
            let percent = String(logContent[percentRange])
            let bpm = String(logContent[bpmRange])
            return ("\(percent)%", bpm)
        }
        
        // 另一種格式
        let bpmRegex = try? NSRegularExpression(pattern: "心率閾值: (\\d+)", options: [])
        let percentRegex = try? NSRegularExpression(pattern: "閾值百分比: (\\d+)", options: [])
        
        if let bpmMatch = bpmRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let bpmRange = Range(bpmMatch.range(at: 1), in: logContent),
           let percentMatch = percentRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let percentRange = Range(percentMatch.range(at: 1), in: logContent) {
            let bpm = String(logContent[bpmRange])
            let percent = String(logContent[percentRange])
            return ("\(percent)%", bpm)
        }
        
        return ("90%", "54")  // 默認值
    }
    
    private func getDetectionErrorType() -> String {
        // 解析漏報或誤報
        if logContent.contains("漏報") {
            return "漏報"
        } else if logContent.contains("誤報") || logContent.contains("誤判") {
            return "誤報"
        }
        
        return "無"  // 默認值
    }
    
    private func getSessionStatus() -> String {
        // 解析會話狀態
        if logContent.contains("誤判") {
            return "系統誤判"
        } else if logContent.contains("漏報") {
            return "系統漏報"
        } else if logContent.contains("正常") {
            return "正常檢測"
        }
        
        // 根據用戶反饋
        if logContent.contains("用戶反饋: 準確") {
            return "正常狀態"
        } else if logContent.contains("用戶反饋: 不準確") {
            if logContent.contains("深度睡眠") || logContent.contains("輕度睡眠") {
                return "系統誤判"
            } else {
                return "系統漏報"
            }
        }
        
        return "正常狀態"  // 默認值
    }
    
    // 調整數據視圖
    private var adjustmentDataView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("心率閾值調整")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let adjustment = getThresholdAdjustment()
                Text(adjustment)
                    .font(.system(size: 12))
                    .foregroundColor(adjustment.contains("+") ? .green : (adjustment.contains("-") ? .orange : .gray))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("確認時間")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (time, change) = getConfirmationTime()
                Text("\(time)秒 \(change)")
                    .font(.system(size: 12))
                    .foregroundColor(change.contains("+") ? .orange : (change.contains("-") ? .green : .gray))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 數據分析方法
    
    private func getDayNumber() -> String {
        // 從日誌名稱提取或計算天數
        return "1"
    }
    
    private func getThresholdAdjustment() -> String {
        // 獲取閾值調整信息
        let adjustRegex = try? NSRegularExpression(pattern: "閾值調整: ([^\\n]+)", options: [])
        
        if let match = adjustRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let adjustRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[adjustRange])
        }
        
        // 檢查可能的增減說明
        if logContent.contains("增加") && logContent.contains("%") {
            let percentRegex = try? NSRegularExpression(pattern: "增加.*?(\\d+\\.?\\d*)%", options: [])
            if let match = percentRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
               let percentRange = Range(match.range(at: 1), in: logContent) {
                return "+\(String(logContent[percentRange]))%"
            }
        } else if logContent.contains("減少") && logContent.contains("%") {
            let percentRegex = try? NSRegularExpression(pattern: "減少.*?(\\d+\\.?\\d*)%", options: [])
            if let match = percentRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
               let percentRange = Range(match.range(at: 1), in: logContent) {
                return "-\(String(logContent[percentRange]))%"
            }
        }
        
        return "無變化" // 默認值
    }
    
    private func getConfirmationTime() -> (Int, String) {
        // 獲取確認時間及變化
        // 尋找確認時間
        let timeRegex = try? NSRegularExpression(pattern: "確認時間: (\\d+)秒", options: [])
        
        if let match = timeRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let timeRange = Range(match.range(at: 1), in: logContent),
           let time = Int(logContent[timeRange]) {
            
            // 檢查是否有變化信息
            if logContent.contains("增加") && logContent.contains("秒") {
                let changeRegex = try? NSRegularExpression(pattern: "增加.*?(\\d+)秒", options: [])
                if let changeMatch = changeRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
                   let changeRange = Range(changeMatch.range(at: 1), in: logContent) {
                    return (time, "+\(String(logContent[changeRange]))秒")
                }
            } else if logContent.contains("減少") && logContent.contains("秒") {
                let changeRegex = try? NSRegularExpression(pattern: "減少.*?(\\d+)秒", options: [])
                if let changeMatch = changeRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
                   let changeRange = Range(changeMatch.range(at: 1), in: logContent) {
                    return (time, "-\(String(logContent[changeRange]))秒")
                }
            }
            
            return (time, "不變")
        }
        
        return (180, "不變") // 默認值
    }
    
    // 格式化原始日誌條目 - 只顯示最後幾條
    private func formatRawLogEntries(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        
        // 獲取最後10條數據記錄
        let dataLines = lines.filter { $0.contains(",") && !$0.contains("Timestamp") }
        if dataLines.count > 0 {
            let lastDataLines = Array(dataLines.suffix(min(10, dataLines.count)))
            return lastDataLines.map { formatDataLine($0) }.joined(separator: "\n")
        }
        
        return "無原始數據記錄"
    }
    
    // 格式化數據行 - 更清晰的格式
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
    
    // 根據睡眠階段獲取顏色
    private var sleepPhaseColor: Color {
        switch viewModel.sleepPhase {
        case .awake:
            return .gray
        case .falling:
            return .blue
        case .light:
            return .green
        case .deep:
            return .purple
        case .rem:
            return .orange
        }
    }
    
    // 新增：設置頁面
    private var settingsView: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 標題改為左上角小標題風格
                    Text("設定")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    
                    // 統一的列表項風格
                    VStack(spacing: 8) {
                        // 睡眠確認時間設定
                        NavigationLink(destination: SleepConfirmationTimeSettingView(viewModel: viewModel)) {
                            settingRow(
                                icon: "clock",
                                title: "睡眠確認時間",
                                iconColor: .blue
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 心率閾值調整 - 導航到新的次頁
                        NavigationLink(destination: HeartRateThresholdSettingView(viewModel: viewModel)) {
                            settingRow(
                                icon: "heart.text.square",
                                title: "心率閾值",
                                iconColor: .red
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 睡眠檢測敏感度 - 導航到新的次頁
                        NavigationLink(destination: SensitivityDetailSettingView(viewModel: viewModel, sleepSensitivity: $sleepSensitivity)) {
                            settingRow(
                                icon: "gauge",
                                title: "檢測敏感度",
                                iconColor: .orange
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 碎片化睡眠 - 新增設定項
                        NavigationLink(destination: FragmentedSleepSettingView(viewModel: viewModel)) {
                            settingRow(
                                icon: "waveform.path.ecg",
                                title: "碎片化睡眠",
                                iconColor: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 年齡組設置 - 導航到新的次頁
                        NavigationLink(destination: AgeGroupDetailSettingView(viewModel: viewModel, selectedAgeGroup: $selectedAgeGroup)) {
                            settingRow(
                                icon: "person.3",
                                title: "年齡組設置",
                                iconColor: .green
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal)
                    
                    // 心率信息視圖
                    VStack(spacing: 0) {
                        Text("心率信息")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 24)
                            .padding(.bottom, 5)
                        
                        HeartRateInfoView(viewModel: viewModel)
                    }
                    
                    // 重設按鈕
                    Button(action: {
                        // 重置設置
                        thresholdOffset = 0.0
                        sleepSensitivity = 0.5
                        viewModel.setUserHeartRateThresholdOffset(0.0)
                        viewModel.setSleepSensitivity(0.5)
                    }) {
                        Text("重設所有設置參數")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
            .background(Color.black)
        }
    }
    
    // 設置行項目通用視圖 - 簡化設計
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
    
    // 格式化日誌文件名
    private func formatLogFilename(_ filename: String) -> String {
        return filename
            .replacingOccurrences(of: "powernap_session_", with: "")
            .replacingOccurrences(of: ".csv", with: "")
    }
    
    // 添加反饋提示視圖
    private var feedbackPromptView: some View {
        ZStack {
            // 半透明背景 - 修改為覆蓋整個屏幕包括安全區域
            Color.black
                .opacity(0.95)
                .edgesIgnoringSafeArea(.all)
            
            // 內容視圖
            GeometryReader { geometry in
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
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .ignoresSafeArea() // 確保完全覆蓋整個屏幕
    }
    
    // 初始反饋問題視圖
    private var initialFeedbackView: some View {
        VStack {
            Text("睡眠檢測準確嗎？")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 5)
            
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
            .padding(.vertical, 10)
            
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
            .padding(.bottom, 5)
        }
        .padding()
    }
    
    // 修改建議調整頁面視圖
    private var suggestionFeedbackView: some View {
        VStack(spacing: 15) {
            Text("需要調整檢測靈敏度？")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 5)
            
            // 簡化的描述文字
            Text("系統已記錄並自動優化設定。")
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
            Text("如需手動調整，您可")
                    .font(.caption)
                .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
            // 前往設置按鈕 - 只導航到設置主頁
            Button(action: {
                viewModel.showingFeedbackPrompt = false
                feedbackStage = .initial
                selectedTab = 3 // 切換到設置頁面
            }) {
                Text("前往設置")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 5)
            
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
            .padding(.bottom, 5)
        }
        .padding()
    }
    
    // 感謝頁面視圖
    private var thanksFeedbackView: some View {
        VStack(spacing: 15) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundColor(.pink)
                .padding(.top, 5)
            
            Text("感謝您的反饋！")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(feedbackWasAccurate ? "我們將繼續優化睡眠檢測" : "您的反饋已記錄")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // 鬧鈴停止UI覆蓋層
    private var alarmStopView: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                    .padding(.top, 20)
                
                Text("小睡結束！")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("現在是時候起來了")
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                
                Button(action: {
                    // 停止鬧鈴
                    viewModel.stopAlarm()
                }) {
                    Text("停止鬧鈴")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .padding()
            .background(Color.black)
            .cornerRadius(15)
            .shadow(radius: 10)
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
    
    // 修復用戶反饋方法
    private func getUserFeedback() -> String {
        // 獲取用戶反饋
        if logContent.contains("用戶反饋: 準確") {
            return "準確"
        } else if logContent.contains("用戶反饋: 不準確") {
            return "不準確"
        } else {
            return "無反饋"
        }
    }
    
    // 修復獲取異常閾值方法
    private func getAnomalyThreshold() -> String {
        // 獲取異常閾值
        let thresholdRegex = try? NSRegularExpression(pattern: "異常閾值: ([0-9]+%[^\\n]+)", options: [])
        
        if let match = thresholdRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let thresholdRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[thresholdRange])
        }
        
        return "8%向下" // 默認值
    }
    
    // 修復累計分數方法
    private func getCumulativeScore() -> Int {
        // 獲取累計異常分數
        let scoreRegex = try? NSRegularExpression(pattern: "累計分數: (\\d+)", options: [])
        
        if let match = scoreRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let scoreRange = Range(match.range(at: 1), in: logContent),
           let score = Int(logContent[scoreRange]) {
            return score
        }
        
        return 0 // 默認值
    }
    
    // 修復系統判定方法
    private func getSystemDetection() -> (String, Bool) {
        // 獲取系統判定結果
        let stateRegex = try? NSRegularExpression(pattern: "系統判定: ([^\\n]+)", options: [])
        
        if let match = stateRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let stateRange = Range(match.range(at: 1), in: logContent) {
            let state = String(logContent[stateRange])
            let aboveThreshold = state.contains("符合閾值") || !state.contains("不符合")
            
            if state.contains("睡眠") {
                return ("睡眠", aboveThreshold)
            } else {
                return ("清醒", aboveThreshold)
            }
        }
        
        // 根據其他信息判斷
        if logContent.contains("檢測到深度睡眠") || logContent.contains("檢測到輕度睡眠") {
            return ("睡眠", true)
        } else if logContent.contains("未檢測到睡眠") {
            return ("清醒", false)
        }
        
        return ("睡眠", true) // 默認值
    }
}

// 自定義PreferenceKey用於避免不必要的更新
struct TabViewHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 心率閾值設置詳細頁面
struct HeartRateThresholdSettingView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: PowerNapViewModel
    
    // 計算當前基礎閾值百分比
    private var basePercentage: Double {
        if let profile = viewModel.currentUserProfile {
            return profile.hrThresholdPercentage
        } else if let ageGroup = viewModel.userSelectedAgeGroup {
            return ageGroup.heartRateThresholdPercentage
        } else {
            return 0.9 // 默認值，如果無法獲取
        }
    }
    
    // 當前閾值顯示
    private var currentThresholdText: String {
        return "RHR的\(Int((basePercentage + viewModel.userHRThresholdOffset) * 100))%"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 當前閾值顯示
                VStack(spacing: 10) {
                    Text("當前心率閾值")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(currentThresholdText)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                    
                    Text("當心率低於此閾值且保持穩定，系統會判定您已進入睡眠狀態")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                
                // 調整按鈕
                VStack(spacing: 12) {
                    // 判定嚴謹按鈕 - 降低閾值
                    Button(action: {
                        // 設置閾值調整為降低5%
                        let newOffset = viewModel.userHRThresholdOffset - 0.05
                        viewModel.setUserHeartRateThresholdOffset(newOffset)
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 18))
                            
                            Text("提高標準 (判定更嚴謹)")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.2))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 判定寬鬆按鈕 - 增加閾值
                    Button(action: {
                        // 設置閾值調整為增加5%
                        let newOffset = viewModel.userHRThresholdOffset + 0.05
                        viewModel.setUserHeartRateThresholdOffset(newOffset)
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 18))
                            
                            Text("降低標準 (判定更寬鬆)")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.2))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                // 說明
                VStack(alignment: .leading, spacing: 8) {
                    Text("心率閾值說明")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text("• 判定嚴謹：降低閾值使系統需要更低的心率才會判定入睡，減少誤判但可能延遲檢測")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("• 判定寬鬆：提高閾值使系統更容易判定入睡，可能更快檢測但增加誤判機率")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }
        .background(Color.black)
        .navigationTitle("心率閾值")
    }
}

// 睡眠檢測敏感度詳細設置頁面
struct SensitivityDetailSettingView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: PowerNapViewModel
    @Binding var sleepSensitivity: Double
    
    // 計算調整值：從-5%到+5%
    private var adjustmentValue: Int {
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
        ScrollView {
            VStack(spacing: 10) { // 縮小整體間距
                // 當前敏感度顯示
                    Text(adjustmentDisplay)
                    .font(.system(size: 32, weight: .medium, design: .rounded)) // 縮小字體
                        .foregroundColor(.white)
                    .padding(.top, 8)
                    .padding(.bottom, 5)
                
                // 嚴謹/中性/寬鬆標籤
                    HStack {
                        Text("嚴謹")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text("中性")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text("寬鬆")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                .padding(.bottom, 5)
                
                // 加減按鈕 - 移到頂部附近
                HStack(spacing: 30) {
                    // 減號按鈕
                    Button(action: {
                        let newValue = max(0, viewModel.sleepSensitivity - 0.1)
                        viewModel.setSleepSensitivity(newValue)
                        sleepSensitivity = newValue
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                            .background(Color(white: 0.2, opacity: 0.3))
                            .cornerRadius(22)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle().size(CGSize(width: 70, height: 60)))
                    
                    // 加號按鈕
                    Button(action: {
                        let newValue = min(1, viewModel.sleepSensitivity + 0.1)
                        viewModel.setSleepSensitivity(newValue)
                        sleepSensitivity = newValue
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                            .background(Color(white: 0.2, opacity: 0.3))
                            .cornerRadius(22)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle().size(CGSize(width: 70, height: 60)))
                }
                .padding(.bottom, 10)
                
                // 說明
                VStack(alignment: .leading, spacing: 8) {
                    Text("敏感度調整說明")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text("• 嚴謹：系統更嚴格判定睡眠狀態，降低誤判率但可能延遲檢測")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("• 寬鬆：系統更寬鬆判定睡眠狀態，可能更快檢測但增加誤判率")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical, 10) // 減少頂部和底部間距
        }
        .background(Color.black)
        .navigationTitle("檢測敏感度")
    }
}

// 年齡組詳細設置頁面
struct AgeGroupDetailSettingView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: PowerNapViewModel
    @Binding var selectedAgeGroup: AgeGroup?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 當前年齡組
                if let currentAgeGroup = viewModel.userSelectedAgeGroup {
                    Text("當前選擇: \(ageGroupTitle(currentAgeGroup))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                
                // 年齡組選項
                VStack(spacing: 10) {
                    ageGroupButtonLarge(title: "青少年 (< 18歲)", description: "偏好更快入睡檢測，閾值設為87.5%", ageGroup: .teen)
                    
                    ageGroupButtonLarge(title: "成人 (18-60歲)", description: "標準檢測設定，閾值設為90%", ageGroup: .adult)
                    
                    ageGroupButtonLarge(title: "銀髮族 (> 60歲)", description: "更嚴謹的檢測，閾值設為93.5%", ageGroup: .senior)
                }
                .padding(.horizontal)
                
                // 說明
                VStack(alignment: .leading, spacing: 8) {
                    Text("年齡組設置說明")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text("選擇您的年齡組可以最佳化睡眠檢測閾值和確認時間。\n• 青少年：更敏感的檢測，確認時間為2分鐘\n• 成人：標準檢測，確認時間為3分鐘\n• 銀髮族：更嚴謹的檢測，確認時間為4分鐘")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }
        .background(Color.black)
        .navigationTitle("年齡組設置")
    }
    
    private func ageGroupTitle(_ ageGroup: AgeGroup) -> String {
        switch ageGroup {
        case .teen: return "青少年"
        case .adult: return "成人"
        case .senior: return "銀髮族"
        }
    }
    
    private func ageGroupButtonLarge(title: String, description: String, ageGroup: AgeGroup) -> some View {
        Button(action: {
            selectedAgeGroup = ageGroup
            viewModel.setUserAgeGroup(ageGroup)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if viewModel.userSelectedAgeGroup == ageGroup {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.userSelectedAgeGroup == ageGroup ? Color(white: 0.25) : Color(white: 0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 心率信息視圖
struct HeartRateInfoView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding()
        .background(Color(white: 0.15))
        .cornerRadius(12)
        .padding(.horizontal)
        .allowsHitTesting(false)
        .focusable(false)
    }
}

// 碎片化睡眠設定頁面
struct FragmentedSleepSettingView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 開關選項
                VStack(spacing: 15) {
                    HStack {
                        Text("啟用碎片化睡眠模式")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { viewModel.fragmentedSleepMode },
                            set: { viewModel.setFragmentedSleepMode($0) }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .purple))
                    }
                    .padding()
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // 說明
                VStack(alignment: .leading, spacing: 12) {
                    Text("碎片化睡眠模式說明")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text("如果您經常經歷睡眠碎片化（頻繁短暫醒來），啟用此模式可以提高睡眠檢測準確度。")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("啟用後的變化：")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                    
                    Text("• 縮短睡眠確認時間以捕捉短暫睡眠")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("• 優化對微覺醒的處理")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("• 調整心率監測模式，適應快速變化")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // 適用情境
                VStack(alignment: .leading, spacing: 8) {
                    Text("適用情境")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text("• 淺眠者：容易短暫醒來的睡眠習慣")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("• 環境敏感者：對環境聲音或光線敏感")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text("• 午休困難者：難以持續維持午休狀態")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }
        .background(Color.black)
        .navigationTitle("碎片化睡眠")
    }
}

#Preview {
    ContentView()
}
