//
//  ContentView.swift
//  powernapv2new Watch App
//
//  Created by michaellee on 4/27/25.
//

import SwiftUI
import UserNotifications
import HealthKit

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
    
    // 新增：跟踪重置選項
    @State private var showingResetOptions: Bool = false
    
    // 新增：跟踪系統判定
    @State private var systemDetectionDisplay: String = "-"
    
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
    
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showOnboarding: Bool = false
    
    // 分享匿名使用資料開關（設定頁）
    @State private var shareUsageSetting: Bool = {
        if let saved = UserDefaults.standard.object(forKey: "shareUsage") as? Bool {
            return saved
        }
        return true
    }()
    
    // 抽出主 TabView，避免在 if-else 外掛修飾符造成 Any 型別
    @ViewBuilder
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            // 主頁面
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
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

            // 設置
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                settingsView
            }
            .tag(1)

            // 高級日誌
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                AdvancedLogsView()
            }
            .tag(2)

            // 測試功能
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                testFunctionsView
            }
            .tag(3)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: TabViewHeightPreference.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(TabViewHeightPreference.self) { _ in
            if logFiles.isEmpty { loadLogFiles() }
            if thresholdOffset == 0.0 && sleepSensitivity == 0.5 {
                thresholdOffset = viewModel.userHRThresholdOffset
                sleepSensitivity = viewModel.sleepSensitivity
                selectedAgeGroup = viewModel.userSelectedAgeGroup
            }
        }
    }
    
    var body: some View {
        ZStack {
        if showOnboarding {
            OnboardingView(showOnboarding: $showOnboarding)
        } else {
            mainTabView
                .overlay(
                    Group {
                        if viewModel.showingFeedbackPrompt { feedbackPromptView }
                        if viewModel.showingAlarmStopUI { alarmStopView }
                    }
                )
        }
        }
    }
    
    // 準備狀態視圖 - 使用官方推薦的WatchOS Picker實現
    private var preparingView: some View {
        VStack(spacing: 15) {
            // 修改為根據確認時間動態調整的時間範圍
            Picker(selection: $viewModel.napMinutes, label: Text(NSLocalizedString("minutes_label", comment: "分鐘數選擇標籤"))) {
                ForEach(viewModel.validNapDurationRange, id: \.self) { minutes in
                    Text("\(minutes)")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .tag(minutes)
                    }
                }
            .pickerStyle(WheelPickerStyle())
            .frame(height: 100)
            .onAppear {
                // 確保在視圖載入時檢查並修正選擇的值
                viewModel.ensureValidNapDuration()
            }
                
                // 開始按鈕
                Button(action: {
                // 轉換為秒
                viewModel.napDuration = Double(viewModel.napMinutes) * 60
                    viewModel.startNap()
                }) {
                    Text(NSLocalizedString("start_rest_button", comment: "開始休息按鈕"))
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
                    Text(NSLocalizedString("dev_test_functions", comment: "開發測試功能"))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    .padding(.top, 10)
                    .padding(.bottom, 5)
                    
                    // 心率資訊區塊
                    VStack(spacing: 10) {
                        HStack {
                            Text(NSLocalizedString("heart_rate", comment: "心率"))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(viewModel.currentHeartRate))")
                                .foregroundColor(.green)
                                .font(.system(size: 18, weight: .bold))
                            Text(NSLocalizedString("bpm", comment: "BPM"))
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                        
                        HStack {
                            Text(NSLocalizedString("resting_heart_rate", comment: "靜止心率"))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(viewModel.restingHeartRate))")
                                .foregroundColor(.orange)
                                .font(.system(size: 18, weight: .bold))
                            Text(NSLocalizedString("bpm", comment: "BPM"))
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                        
                        HStack {
                            Text(NSLocalizedString("threshold", comment: "閾值"))
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
                            Text(NSLocalizedString("movement_intensity", comment: "運動強度"))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.4f", viewModel.currentAcceleration))
                                .foregroundColor(viewModel.currentAcceleration > viewModel.motionThreshold ? .red : .green)
                                .font(.system(size: 18, weight: .bold))
                        }
                        
                        HStack {
                            Text(NSLocalizedString("threshold", comment: "閾值"))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.3f", viewModel.motionThreshold))
                                .foregroundColor(.blue)
                                .font(.system(size: 18, weight: .bold))
                        }
                        
                        HStack {
                            Text(NSLocalizedString("movement_state", comment: "運動狀態"))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(viewModel.isResting ? NSLocalizedString("resting", comment: "靜止") : NSLocalizedString("active", comment: "活動中"))
                                .foregroundColor(viewModel.isResting ? .green : .red)
                                .font(.system(size: 18, weight: .bold))
                        }
                        
                        HStack {
                            Text(NSLocalizedString("sleep_state", comment: "睡眠狀態"))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(viewModel.isProbablySleeping ? NSLocalizedString("sleeping", comment: "可能睡眠中") : NSLocalizedString("awake", comment: "清醒"))
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
                        Text(NSLocalizedString("test_alarm_function", comment: "測試鬧鈴功能"))
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
                        Text(NSLocalizedString("test_feedback_prompt", comment: "測試反饋提示"))
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
                    Text(NSLocalizedString("scenario_test_area", comment: "情境測試區"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                    
                    // 情境1：用戶入睡，系統正確檢測到
                    Button(action: {
                        feedbackStage = .initial
                        viewModel.simulateScenario1Feedback()
                    }) {
                        Text(NSLocalizedString("scenario_1_correct_detection", comment: "情境1：正確檢測睡眠"))
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
                        Text(NSLocalizedString("scenario_2_no_detection", comment: "情境2：未檢測到睡眠"))
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
                        Text(NSLocalizedString("scenario_3_false_positive", comment: "情境3：誤判為睡眠"))
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
                        Text(NSLocalizedString("scenario_4_correct_no_detection", comment: "情境4：正確未檢測"))
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
                        Text(NSLocalizedString("test_alarm_flow", comment: "測試鬧鈴流程"))
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

                    // 新增：強制觸發閾值優化按鈕
                    Button(action: {
                        viewModel.forceReallyOptimizeThreshold()
                    }) {
                        Text(NSLocalizedString("force_really_optimize", comment: "真正強制優化"))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(25)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
                    
                    // 新增：產生高級日誌測試檔按鈕
                    Button(action: generateFakeAdvancedLogFile) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text(NSLocalizedString("generate_advanced_log_test_file", comment: "產生高級日誌測試檔"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color(white: 0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
                .padding(.bottom, 20)
            }
    }
    
    // 監測狀態視圖
    private var monitoringView: some View {
        VStack {
            Spacer().frame(height: 20)
            
            Spacer()
            
            // 等待文字 - 接近置中
            // 根據睡眠狀態顯示不同的訊息
            if viewModel.napPhase == .sleeping {
                // 已開始倒數階段 - 顯示倒數計時
                Text(timeString(from: viewModel.remainingTime))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // 睡眠階段指示器
                Text(sleepPhaseText)
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            } else {
                // 監測中狀態 - 只顯示設定時間與簡單提示
                Text(timeString(from: viewModel.napDuration))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))

                Text(NSLocalizedString("monitoring_status", comment: "監測中狀態"))
                    .font(.system(size: 14))
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
                    Text(NSLocalizedString("confirm_cancel", comment: "確認取消按鈕"))
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
                    Text(NSLocalizedString("continue_monitoring", comment: "繼續監測按鈕"))
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
                Text(NSLocalizedString("cancel_button", comment: "取消按鈕"))
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
                Text(NSLocalizedString("cancel_button", comment: "取消按鈕"))
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
            Text(NSLocalizedString("sleep_data_records", comment: "睡眠數據記錄"))
                .font(.headline)
                .foregroundColor(.white)
                    .padding(.vertical, 5)
            
                LazyVStack(spacing: 5) { // 減少間距為5
                    if logFiles.isEmpty {
                        Text(NSLocalizedString("no_records", comment: "尚無記錄"))
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
                            Text(NSLocalizedString("refresh", comment: "重新整理"))
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
                        Text(NSLocalizedString("back_button", comment: "返回按鈕"))
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
                    Text(NSLocalizedString("loading", comment: "載入中狀態"))
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
                            Text(NSLocalizedString("raw_data_records", comment: "原始數據記錄"))
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
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("sleep_status_analysis", comment: "睡眠狀態分析"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 4)
            
            // 新增：本次狀態顯示
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("current_status", comment: "本次狀態"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(getSleepSessionStatus())
                        .font(.system(size: 12))
                        .foregroundColor(getSleepSessionStatus() == "已入睡" ? .green : .gray)
                }
                
                Spacer()
                
                // 僅供參考標記
                if getSleepSessionStatus() == "未入睡" || getSleepSessionStatus() == "監測中取消" {
                    Text(NSLocalizedString("reference_only_not_optimized", comment: "僅供參考，未納入優化"))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color(white: 0.15))
            .cornerRadius(8)
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
                    
                    Text(NSLocalizedString("heart_rate_data", comment: "心率數據"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text("\(getAverageSleepHR()) \(NSLocalizedString("bpm", comment: "BPM")) (RHR\(NSLocalizedString("of", comment: "的"))\(getSleepHRPercentage()))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("deviation_ratio", comment: "偏離比例"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (deviation, isDown) = getHRDeviation()
                Text("\(deviation) (\(isDown ? NSLocalizedString("down", comment: "向下") : NSLocalizedString("up", comment: "向上")))")
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
                Text(NSLocalizedString("anomaly_score", comment: "異常評分"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let score = getAnomalyScore()
                Text("\(score) (\(NSLocalizedString("below", comment: "低於"))\(getAnomalyThreshold())\(NSLocalizedString("threshold", comment: "閾值")))")
                    .font(.system(size: 12))
                    .foregroundColor(score > 3 ? .orange : .green)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("cumulative_score", comment: "累計分數"))
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
                Text(NSLocalizedString("threshold_percentage", comment: "閾值百分比"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                let (percent, bpm) = getThresholdValues()
                Text("\(percent) (\(bpm) BPM)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("system_detection", comment: "系統判定"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (detected, aboveThreshold) = getSystemDetection()
                Text("\(detected) (\(aboveThreshold ? NSLocalizedString("meets_threshold", comment: "符合閾值") : NSLocalizedString("does_not_meet_threshold", comment: "不符合閾值")))")
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
                Text(NSLocalizedString("false_positive_negative", comment: "漏/誤報"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(getDetectionErrorType())
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("user_feedback", comment: "用戶反饋"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(getUserFeedback())
                    .font(.system(size: 12))
                    .foregroundColor(getUserFeedback() == "準確" ? .green : (getUserFeedback() == "無" ? .gray : .orange))
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
                Text(NSLocalizedString("detection_precision", comment: "判斷準確率"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let precision = getPrecisionData()
                Text("\(precision)%")
                    .font(.system(size: 12))
                    .foregroundColor(Double(precision) ?? 0 > 85 ? .green : .orange)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("sleep_recognition_rate", comment: "睡眠識別率"))
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
    
    // 調整數據視圖
    private var adjustmentDataView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("hr_threshold_adjustment", comment: "心率閾值調整"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                let adjustment = getThresholdAdjustment()
                let timeWithSeconds = "\(getConfirmationTime().0) \(NSLocalizedString("seconds_format", comment: "秒"))"
                let displayText = adjustment.isEmpty ? timeWithSeconds : "\(timeWithSeconds) \(adjustment)"
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundColor(getConfirmationTime().1.contains("+") ? .orange : (getConfirmationTime().1.contains("-") ? .green : .gray))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("confirmation_time", comment: "確認時間"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                let (time, change) = getConfirmationTime()
                let secondsText = NSLocalizedString("seconds_format", comment: "秒")
                let displayText = change.isEmpty ? "\(time) \(secondsText)" : "\(time) \(secondsText) \(change)"
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundColor(change.contains("+") ? .orange : (change.contains("-") ? .green : .gray))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
    
    // 獲取精度數據
    private func getPrecisionData() -> String {
        // 新格式：從日誌行中提取準確率數據
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("準確率") || line.contains("判斷準確率") {
                let precisionRegex = try? NSRegularExpression(pattern: "準確率[^\\d]*(\\d+\\.?\\d*)%", options: [])
                if let match = precisionRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let precisionRange = Range(match.range(at: 1), in: line) {
                    return String(line[precisionRange])
                }
            }
        }
        
        // 舊格式
        let precisionRegex = try? NSRegularExpression(pattern: "準確率: (\\d+)%", options: [])
        if let match = precisionRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let precisionRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[precisionRange])
        }
        
        // 根據反饋推測準確率
        if getUserFeedback() == "準確" {
            return "100"
        } else if getUserFeedback() == "誤報" || getUserFeedback() == "漏報" {
            return "0"
        }
        
        return "-"
    }
    
    private func getRecallData() -> String {
        // 新格式：從日誌行中提取識別率數據
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("識別率") || line.contains("睡眠識別率") {
                let recallRegex = try? NSRegularExpression(pattern: "識別率[^\\d]*(\\d+\\.?\\d*)%", options: [])
                if let match = recallRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let recallRange = Range(match.range(at: 1), in: line) {
                    return String(line[recallRange])
                }
            }
        }
        
        // 舊格式
        let recallRegex = try? NSRegularExpression(pattern: "識別率: (\\d+)%", options: [])
        if let match = recallRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let recallRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[recallRange])
        }
        
        // 根據反饋推測識別率
        if getSleepSessionStatus() == "已入睡" && getUserFeedback() == "準確" {
            return "100"
        } else if getSleepSessionStatus() == "未入睡" && getUserFeedback() == "誤報" {
            return "100"
        } else if getUserFeedback() == "漏報" {
            return "0"
        }
        
        return "-"
    }
    
    private func getAverageSleepHR() -> String {
        // 新格式匹配：[時間戳] HR: 值 - 狀態
        let newFormatRegex = try? NSRegularExpression(pattern: "HR: (\\d+\\.?\\d*)", options: [])
        var heartRates = [Double]()
        
        // 遍歷日誌行提取心率
        for line in logContent.components(separatedBy: .newlines) {
            if let match = newFormatRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
               let hrRange = Range(match.range(at: 1), in: line),
               let hr = Double(line[hrRange]) {
                heartRates.append(hr)
            }
        }
        
        if !heartRates.isEmpty {
            let avgHR = heartRates.reduce(0, +) / Double(heartRates.count)
            return "\(Int(avgHR))"
        }
        
        // 舊格式：直接從平均心率記錄中提取
        let avgHRRegex = try? NSRegularExpression(pattern: "平均心率: (\\d+)", options: [])
        if let match = avgHRRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let hrRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[hrRange])
        }
        
        return "-"  // 無數據符號
    }
    
    private func getSleepHRPercentage() -> String {
        // 從日誌中提取或計算睡眠心率佔RHR的百分比
        let avgHR = Double(getAverageSleepHR()) ?? 0
        if avgHR == 0 || getAverageSleepHR() == "-" {
            return "-" // 如果沒有心率數據，直接返回-
        }
        
        // 嘗試從新格式中提取靜息心率
        let rhrNewRegex = try? NSRegularExpression(pattern: "RHR: (\\d+\\.?\\d*)", options: [])
        
        if let match = rhrNewRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let rhrRange = Range(match.range(at: 1), in: logContent),
           let rhr = Double(logContent[rhrRange]), rhr > 0 {
            let percentage = (avgHR / rhr) * 100
            return "\(Int(percentage))%"
        }
        
        // 嘗試從舊格式中提取靜息心率
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
        
        return "-"  // 修改為無數據符號
    }
    
    private func getHRDeviation() -> (String, Bool) {
        // 新格式中的心率偏離信息
        // 從日誌行中查找包含偏離比例的信息
        let deviationRegex = try? NSRegularExpression(pattern: "偏離: ([+-]?\\d+\\.?\\d*)%", options: [])
        
        for line in logContent.components(separatedBy: .newlines) {
            if let match = deviationRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
               let deviationRange = Range(match.range(at: 1), in: line) {
                let deviationStr = String(line[deviationRange])
                let isDown = deviationStr.contains("-") || line.contains("向下")
                return ("\(deviationStr)", isDown)
            }
        }
        
        // 檢查是否包含"向下"或"向上"關鍵詞
        if logContent.contains("向下") {
            // 嘗試提取數字
            let numRegex = try? NSRegularExpression(pattern: "(-?\\d+\\.?\\d*)%[^\\d]*向下", options: [])
            if let match = numRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
               let numRange = Range(match.range(at: 1), in: logContent) {
                return (String(logContent[numRange]), true)
            }
            return ("5", true) // 預設值
        } else if logContent.contains("向上") {
            let numRegex = try? NSRegularExpression(pattern: "(\\d+\\.?\\d*)%[^\\d]*向上", options: [])
            if let match = numRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
               let numRange = Range(match.range(at: 1), in: logContent) {
                return (String(logContent[numRange]), false)
            }
            return ("5", false) // 預設值
        }
        
        // 原有的解析方式
        let oldDeviationRegex = try? NSRegularExpression(pattern: "偏離比例: ([+-]?\\d+\\.?\\d*)%", options: [])
        
        if let match = oldDeviationRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let deviationRange = Range(match.range(at: 1), in: logContent) {
            let deviationStr = String(logContent[deviationRange])
            let isDown = deviationStr.contains("-") || logContent.contains("向下")
            return ("\(deviationStr)%", isDown)
        }
        
        // 嘗試從原始心率數據計算偏離
        if let avgHR = Double(getAverageSleepHR()), avgHR > 0 {
            // 嘗試獲取靜息心率或預期心率
            let rhrRegex = try? NSRegularExpression(pattern: "RHR: (\\d+\\.?\\d*)", options: [])
            if let match = rhrRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
               let rhrRange = Range(match.range(at: 1), in: logContent),
               let rhr = Double(logContent[rhrRange]), rhr > 0 {
                // 計算偏離百分比 (HR - RHR) / RHR * 100
                let deviation = (avgHR - rhr) / rhr * 100
                let isDown = deviation < 0
                return (String(format: "%.1f", abs(deviation)), isDown)
            }
        }
        
        return ("-", true)  // 修改為無數據符號
    }
    
    private func getAnomalyScore() -> Int {
        // 新格式：直接尋找包含異常評分的行
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("異常評分:") || line.contains("異常評分：") {
                let scoreRegex = try? NSRegularExpression(pattern: "異常評分[：:] *(\\d+)", options: [])
                if let match = scoreRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let scoreRange = Range(match.range(at: 1), in: line),
                   let score = Int(line[scoreRange]) {
                    return score
                }
            }
        }
        
        // 舊格式解析
        let anomalyRegex = try? NSRegularExpression(pattern: "異常評分: (\\d+)", options: [])
        
        if let match = anomalyRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let anomalyRange = Range(match.range(at: 1), in: logContent),
           let score = Int(logContent[anomalyRange]) {
            return score
        }
        
        // 檢查是否顯示了具體異常狀態
        if logContent.contains("暫時異常") {
            return 5
        } else if logContent.contains("持久異常") {
            return 8
        } else if logContent.contains("需要重校準") {
            return 12
        }
        
        // 檢查是否有異常字眼
        if logContent.contains("異常") && !logContent.contains("無異常") {
            return 3
        }
        
        return 0  // 保留0作為無異常的標準值
    }
    
    private func getAnomalyThreshold() -> String {
        // 新格式：查找包含閾值的行
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("閾值") && line.contains("%") {
                let thresholdRegex = try? NSRegularExpression(pattern: "閾值[^\\d]*(\\d+)%", options: [])
                if let match = thresholdRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let thresholdRange = Range(match.range(at: 1), in: line) {
                    return String(line[thresholdRange])
                }
            }
        }
        
        // 舊格式
        let thresholdRegex = try? NSRegularExpression(pattern: "異常閾值: (\\d+)%", options: [])
        
        if let match = thresholdRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let thresholdRange = Range(match.range(at: 1), in: logContent) {
            return "\(logContent[thresholdRange])"
        }
        
        return "8"  // 保留默認閾值
    }
    
    private func getCumulativeScore() -> String {
        // 新格式：查找包含累計分數的行
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("累計分數") || line.contains("累積分數") {
                let scoreRegex = try? NSRegularExpression(pattern: "累[計積]分數[^\\d]*(\\d+\\.?\\d*)", options: [])
                if let match = scoreRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let scoreRange = Range(match.range(at: 1), in: line) {
                    return String(line[scoreRange])
                }
            }
        }
        
        // 舊格式
        let scoreRegex = try? NSRegularExpression(pattern: "累計分數: (\\d+)", options: [])
        
        if let match = scoreRegex?.firstMatch(in: logContent, options: [], range: NSRange(logContent.startIndex..., in: logContent)),
           let scoreRange = Range(match.range(at: 1), in: logContent) {
            return String(logContent[scoreRange])
        }
        
        return "-"  // 修改為無數據符號
    }
    
    private func getThresholdValues() -> (String, String) {
        // 新格式：從日誌行中提取閾值
        for line in logContent.components(separatedBy: .newlines) {
            // 尋找包含閾值百分比和BPM值的行
            if (line.contains("閾值") || line.contains("threshold")) && line.contains("%") && line.contains("BPM") {
                let thresholdRegex = try? NSRegularExpression(pattern: "閾值[^\\d]*(\\d+\\.?\\d*)%[^\\d]*(\\d+\\.?\\d*) *BPM", options: [.caseInsensitive])
                if let match = thresholdRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let percentRange = Range(match.range(at: 1), in: line),
                   let bpmRange = Range(match.range(at: 2), in: line) {
                    let percent = String(line[percentRange])
                    let bpm = String(line[bpmRange])
                    return ("\(percent)%", bpm)
                }
            }
        }
        
        // 舊格式：提取閾值百分比和具體BPM值
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
        
        // 嘗試從心率數據中推算
        if let avgHR = Double(getAverageSleepHR()), avgHR > 0 {
            // 假設閾值是RHR的85%（一個合理的默認值）
            let estimatedThreshold = Int(avgHR * 0.85)
            return ("85%", "\(estimatedThreshold)")
        }
        
        return ("-", "-")  // 修改為無數據符號
    }
    
    private func getSystemDetection() -> (String, Bool) {
        // 新格式：從日誌行中提取系統判定結果
        for line in logContent.components(separatedBy: .newlines) {
            // 檢查是否包含休息中或初步休息
            if line.contains(NSLocalizedString("deep_rest", comment: "休息中")) || line.contains("初步休息") {
                return ("睡眠", true)
            }
            
            // 檢查系統判定結果
            if line.contains("系統判定") {
                if line.contains("睡眠") {
                    let aboveThreshold = !line.contains("不符合閾值")
                    return ("睡眠", aboveThreshold)
                } else if line.contains("未檢測到") || line.contains("未達標準") {
                    return ("未檢測到睡眠", false)
                }
            }
        }
        
        // 舊格式解析
        if logContent.contains("檢測到睡眠") || logContent.contains("系統成功檢測到睡眠") {
            return ("睡眠", true)
        } else if logContent.contains("未檢測到睡眠") || logContent.contains("系統未檢測到睡眠") {
            return ("未檢測到睡眠", false)
        } else if logContent.contains("未達入睡標準") {
            return ("未達入睡標準", false)
        }
        
        // 根據sleepState判斷
        if logContent.contains(NSLocalizedString("deep_rest", comment: "休息中")) || logContent.contains("初步休息") {
            return ("睡眠", true)
        } else if logContent.contains("清醒") || logContent.contains("休息") {
            if getSleepSessionStatus() == "未入睡" {
                return ("未檢測到睡眠", false)
            } else {
                return ("清醒", false)
            }
        }
        
        // 根據本次狀態判定
        if getSleepSessionStatus() == "已入睡" {
            return ("睡眠", true)
        } else if getSleepSessionStatus() == "未入睡" {
            return ("未檢測到睡眠", false)
        }
        
        return ("-", false)  // 無數據符號
    }
    
    private func getDetectionErrorType() -> String {
        // 新格式：從日誌行中提取漏報或誤報信息
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("漏報") {
                return "漏報"
            } else if line.contains("誤報") || line.contains("誤判") {
                return "誤報"
            }
        }
        
        // 根據UI顯示判斷
        if getUserFeedback() == "漏報" {
            return "漏報"
        } else if getUserFeedback() == "誤報" {
            return "誤報"
        }
        
        return "無"  // 保留無誤報/漏報的標準值
    }
    
    private func getUserFeedback() -> String {
        // 新格式：從日誌行中提取用戶反饋
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("用戶反饋") {
                if line.contains("準確") {
                    return "準確"
                } else if line.contains("不準確") || line.contains("誤報") {
                    return "誤報"
                } else if line.contains("漏報") {
                    return "漏報"
                }
            }
        }
        
        // 舊格式處理
        if logContent.contains("用戶反饋: 準確") {
            return "準確"
        } else if logContent.contains("用戶反饋: 不準確") || logContent.contains("用戶反饋: 誤報") {
            return "誤報"
        } else if logContent.contains("用戶反饋: 漏報") {
            return "漏報"
        } else if viewModel.lastFeedbackType != .unknown {
            // 從ViewModel中獲取最新反饋
            switch viewModel.lastFeedbackType {
            case .accurate:
                return "準確"
            case .falsePositive:
                return "誤報"
            case .falseNegative:
                return "漏報"
            default:
                return "無"
            }
        }
        
        return "無"  // 沒有反饋時顯示「無」而非「-」
    }
    
    private func getThresholdAdjustment() -> String {
        // 新格式：從日誌行中提取閾值調整信息
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("閾值調整") {
                // 提取調整值
                let adjustRegex = try? NSRegularExpression(pattern: "閾值調整[^\\d+-]*([+-]?\\d+\\.?\\d*)%", options: [])
                if let match = adjustRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let adjustRange = Range(match.range(at: 1), in: line) {
                    let adjustment = String(line[adjustRange])
                    if adjustment.contains("+") || adjustment.contains("-") {
                        return adjustment + "%"
                    } else if Double(adjustment) ?? 0 > 0 {
                        return "+" + adjustment + "%"
                    } else {
                        return adjustment + "%"
                    }
                }
            }
        }
        
        // 舊格式
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
        
        return "-" // 修改為無數據符號
    }
    
    private func getConfirmationTime() -> (Int, String) {
        // 新格式：從日誌行中提取確認時間信息
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains("確認時間") && line.contains("秒") {
                // 提取時間值
                let timeRegex = try? NSRegularExpression(pattern: "確認時間[^\\d]*(\\d+)秒", options: [])
                if let match = timeRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let timeRange = Range(match.range(at: 1), in: line),
                   let time = Int(line[timeRange]) {
                    
                    // 檢查是否包含變化信息
                    if line.contains("增加") || line.contains("+") {
                        let changeRegex = try? NSRegularExpression(pattern: "增加[^\\d]*([+-]?\\d+)秒|\\+([\\d]+)秒", options: [])
                        if let changeMatch = changeRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                           let changeRange = Range(changeMatch.range(at: 1), in: line),
                           let seconds = Int(line[changeRange]) {
                            return (time, "+\(seconds)秒")
                        }
                        return (time, "+秒") // 有增加但未找到具體數值
                    } else if line.contains("減少") || line.contains("-") {
                        let changeRegex = try? NSRegularExpression(pattern: "減少[^\\d]*([+-]?\\d+)秒|-([\\d]+)秒", options: [])
                        if let changeMatch = changeRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                           let changeRange = Range(changeMatch.range(at: 1), in: line),
                           let seconds = Int(line[changeRange]) {
                            return (time, "-\(seconds)秒")
                        }
                        return (time, "-秒") // 有減少但未找到具體數值
                    }
                    
                    return (time, "不變")
                }
            }
        }
        
        // 舊格式
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
        
        // 如果僅有確認時間而無更改信息
        for line in logContent.components(separatedBy: .newlines) {
            let simpleTimeRegex = try? NSRegularExpression(pattern: "(\\d+)秒", options: [])
            if line.contains("確認") && line.contains("秒") {
                if let match = simpleTimeRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                   let timeRange = Range(match.range(at: 1), in: line),
                   let time = Int(line[timeRange]) {
                    return (time, "不變")
                }
            }
        }
        
        return (0, "-") // 修改為無數據符號
    }
    
    // 格式化原始日誌條目 - 只顯示最後幾條
    private func formatRawLogEntries(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        
        // 新格式：尋找包含HR:的行
        let dataLines = lines.filter { 
            $0.contains("HR:") || ($0.contains(",") && !$0.contains("Timestamp")) 
        }
        if dataLines.count > 0 {
            let lastDataLines = Array(dataLines.suffix(min(10, dataLines.count)))
            return lastDataLines.map { formatDataLine($0) }.joined(separator: "\n")
        }
        
        return NSLocalizedString("no_raw_data", comment: "無原始數據記錄")
    }
    
    // 格式化數據行 - 支持新舊兩種格式
    private func formatDataLine(_ line: String) -> String {
        // 新格式: [時間戳] HR: 數值 - 狀態
        if line.contains("HR:") && line.contains("[") {
            // 已經是我們所需的格式，直接返回
            return line.trimmingCharacters(in: .whitespaces)
        }
        
        // 舊格式處理邏輯
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
    
    // 根據睡眠階段獲取文本
    private var sleepPhaseText: String {
        switch viewModel.sleepPhase {
        case .awake:
            return "清醒"
        case .falling:
            return "即將入睡"
        case .light:
            return "初步休息"
        case .deep:
            return NSLocalizedString("deep_rest", comment: "休息中")
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
                    Text(NSLocalizedString("settings", comment: "設定"))
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
                                title: NSLocalizedString("sleep_confirmation_time_setting", comment: "睡眠確認時間"),
                                iconColor: .blue
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 心率閾值調整 - 導航到新的次頁
                        NavigationLink(destination: HeartRateThresholdSettingView(viewModel: viewModel)) {
                            settingRow(
                                icon: "heart.text.square",
                                title: NSLocalizedString("heart_rate_threshold_setting", comment: "心率閾值"),
                                iconColor: .red
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 睡眠檢測敏感度 - 導航到新的次頁
                        NavigationLink(destination: SensitivityDetailSettingView(viewModel: viewModel, sleepSensitivity: $sleepSensitivity)) {
                            settingRow(
                                icon: "gauge",
                                title: NSLocalizedString("detection_sensitivity_setting", comment: "檢測敏感度"),
                                iconColor: .orange
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 碎片化睡眠 - 新增設定項
                        NavigationLink(destination: FragmentedSleepSettingView(viewModel: viewModel)) {
                            settingRow(
                                icon: "waveform.path.ecg",
                                title: NSLocalizedString("fragmented_sleep_setting", comment: "碎片化睡眠"),
                                iconColor: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 年齡組設置 - 導航到新的次頁
                        NavigationLink(destination: AgeGroupDetailSettingView(viewModel: viewModel, selectedAgeGroup: $selectedAgeGroup)) {
                            settingRow(
                                icon: "person.3",
                                title: NSLocalizedString("age_group_setting", comment: "年齡組設置"),
                                iconColor: .green
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // 資料分享設定 - 導航至次頁
                        NavigationLink(destination: ShareUsageSettingView(shareUsage: $shareUsageSetting)) {
                            settingRow(
                                icon: "hand.raised.fill",
                                title: NSLocalizedString("data_sharing_setting", comment: "資料分享"),
                                iconColor: .yellow
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // 說明 - 跳轉到 InfoMenuView
                        NavigationLink(destination: InfoMenuView()) {
                            settingRow(
                                icon: "info.circle",
                                title: NSLocalizedString("help_setting", comment: "說明"),
                                iconColor: .cyan
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal)
                    
                    // 心率信息視圖
                    VStack(spacing: 0) {
                        Text(NSLocalizedString("heart_rate_info_title", comment: "心率信息"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 24)
                            .padding(.bottom, 5)
                        
                        HeartRateInfoView(viewModel: viewModel)
                    }
                    
                    // 重設按鈕區域 - 改為兩個按鈕
                    VStack(spacing: 10) {
                        // 重設心率閾值和敏感度
                        Button(action: {
                            // 心率閾值和敏感度重置邏輯
                            thresholdOffset = 0.0
                            sleepSensitivity = 0.5
                            viewModel.setUserHeartRateThresholdOffset(0.0)
                            viewModel.setSleepSensitivity(0.5)
                        }) {
                            Text(NSLocalizedString("reset_hr_sensitivity", comment: "重設心率&靈敏度"))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 重置所有參數
                        Button(action: {
                            // 心率閾值和敏感度重置邏輯
                            thresholdOffset = 0.0
                            sleepSensitivity = 0.5
                            viewModel.setUserHeartRateThresholdOffset(0.0)
                            viewModel.setSleepSensitivity(0.5)
                            
                            // 額外重置確認時間
                            viewModel.resetSleepConfirmationTime()
                            
                            // 重置異常評分和累計分數
                            viewModel.resetAllAnomalyScores()
                            
                            // 重置碎片化睡眠模式（如果啟用）
                            if viewModel.fragmentedSleepMode {
                                viewModel.setFragmentedSleepMode(false)
                            }
                        }) {
                            Text(NSLocalizedString("reset_all_parameters", comment: "重置所有參數"))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
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
            Text(NSLocalizedString("sleep_detection_accurate_question", comment: "睡眠檢測準確嗎？"))
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
                }) {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                        Text(NSLocalizedString("accurate", comment: "準確"))
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
                        Text(NSLocalizedString("inaccurate", comment: "不準確"))
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
                Text(NSLocalizedString("not_now_evaluation", comment: "暫不評價"))
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
            Text(NSLocalizedString("need_adjust_sensitivity", comment: "需要調整檢測靈敏度？"))
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 5)
            
            // 簡化的描述文字
            Text(NSLocalizedString("system_recorded_optimized", comment: "系統已記錄並自動優化設定。"))
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
            Text(NSLocalizedString("manual_adjust_hint", comment: "如需手動調整，您可"))
                    .font(.caption)
                .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
            // 前往設置按鈕 - 只導航到設置主頁
            Button(action: {
                viewModel.showingFeedbackPrompt = false
                feedbackStage = .initial
                selectedTab = 1 // 切換到設置頁面 (設定頁現為第二頁)
            }) {
                Text(NSLocalizedString("go_to_settings", comment: "前往設置"))
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
                Text(NSLocalizedString("later", comment: "稍後再說"))
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
            
            Text(NSLocalizedString("thanks_feedback", comment: "感謝您的反饋！"))
                .font(.headline)
                .foregroundColor(.white)
            
            Text(feedbackWasAccurate ? NSLocalizedString("continue_optimize", comment: "我們將繼續優化睡眠檢測") : NSLocalizedString("feedback_recorded", comment: "您的反饋已記錄"))
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            // 自動在2秒後關閉反饋提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                viewModel.showingFeedbackPrompt = false
                feedbackStage = .initial
            }
        }
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
                
                Text(NSLocalizedString("nap_ended_title", comment: "小睡結束標題"))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(NSLocalizedString("time_to_wake_up", comment: "起來時間提示"))
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                
                Button(action: {
                    // 停止鬧鈴
                    viewModel.stopAlarm()
                }) {
                    Text(NSLocalizedString("stop_alarm", comment: "停止鬧鈴按鈕"))
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
    
    // 新增：獲取睡眠會話狀態
    private func getSleepSessionStatus() -> String {
        // 新格式：從日誌行中提取睡眠會話狀態
        for line in logContent.components(separatedBy: .newlines) {
            if line.contains(NSLocalizedString("deep_rest", comment: "休息中")) || line.contains("初步休息") {
                return "已入睡"
            } else if line.contains("監測中取消") || line.contains("用戶取消監測") {
                return "監測中取消"
            } else if line.contains("未檢測到睡眠") || line.contains("未達入睡標準") {
                return "未入睡"
            }
            
            // 檢查狀態行
            if line.contains("本次狀態") || line.contains("睡眠狀態") {
                if line.contains("已入睡") {
                    return "已入睡"
                } else if line.contains("未入睡") {
                    return "未入睡"
                } else if line.contains("監測中取消") {
                    return "監測中取消"
                }
            }
        }
        
        // 舊格式
        if logContent.contains("檢測到睡眠") || 
           logContent.contains("系統成功檢測到睡眠") || 
           logContent.contains(NSLocalizedString("deep_rest", comment: "休息中")) || 
           logContent.contains("初步休息") {
            return "已入睡"
        } else if logContent.contains("監測中取消") || 
                  logContent.contains("用戶取消監測") {
            return "監測中取消"
        } else if logContent.contains("未檢測到睡眠") || 
                  logContent.contains("未達入睡標準") ||
                  logContent.contains("系統未檢測到睡眠") {
            return "未入睡"
        } else {
            return "狀態不明"
        }
    }
    
    private func generateFakeAdvancedLogFile() {
        let fakeLogLines = [
            // sessionStart
            "{\"ts\":\"2025-05-23T08:00:00.000Z\",\"type\":\"sessionStart\",\"payload\":{\"thresholdBPM\":60,\"rhr\":65,\"thresholdPercent\":92,\"minDurationSeconds\":180}}",
            // phaseChange
            "{\"ts\":\"2025-05-23T08:01:00.000Z\",\"type\":\"phaseChange\",\"payload\":{\"newPhase\":\"lightSleep\"}}",
            // hr
            "{\"ts\":\"2025-05-23T08:10:00.000Z\",\"type\":\"hr\",\"payload\":{\"bpm\":58,\"phase\":\"lightSleep\",\"acc\":0.01}}",
            // anomaly
            "{\"ts\":\"2025-05-23T08:20:00.000Z\",\"type\":\"anomaly\",\"payload\":{\"score\":2,\"totalScore\":5}}",
            // optimization (長期優化)
            "{\"ts\":\"2025-05-23T08:25:00.000Z\",\"type\":\"optimization\",\"payload\":{\"oldThreshold\":90,\"newThreshold\":92,\"deltaPercent\":2,\"oldDuration\":180,\"newDuration\":195,\"deltaDuration\":15}}",
            // feedback (用戶反饋：誤報)
            "{\"ts\":\"2025-05-23T08:30:00.000Z\",\"type\":\"feedback\",\"payload\":{\"type\":\"falsePositive\",\"accurate\":false}}",
            // sessionEnd（短期調整後，閾值+2%，確認時間+15秒）
            "{\"ts\":\"2025-05-23T08:31:00.000Z\",\"type\":\"sessionEnd\",\"payload\":{\"avgSleepHR\":62,\"rhr\":65,\"thresholdBPM\":62,\"thresholdPercent\":94,\"minDurationSeconds\":195,\"deviationPercent\":3.3,\"anomalyScore\":2,\"cumulativeScore\":5,\"deltaPercentShort\":2,\"deltaDurationShort\":15,\"detectedSleep\":true,\"notes\":\"測試用session\"}}"
        ]
        let content = fakeLogLines.joined(separator: "\n")
        let fileName = "powernap_session_" + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_") + ".log"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("AdvancedLogFiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(fileName)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
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
        let rhr = viewModel.restingHeartRate
        guard rhr > 0 else { return NSLocalizedString("rhr_no_data_format", comment: "RHR的--") }
        let percent = Int(round(viewModel.heartRateThreshold / rhr * 100))
        return String.localizedStringWithFormat(NSLocalizedString("rhr_percentage_format", comment: "RHR的%@"), "\(percent)%")
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 當前閾值顯示
                VStack(spacing: 10) {
                    Text(NSLocalizedString("current_heart_rate_threshold", comment: "當前心率閾值"))
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(currentThresholdText)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                    
                    Text(NSLocalizedString("threshold_description", comment: "當心率低於此閾值且保持穩定，系統會判定您已進入睡眠狀態"))
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
                            
                            Text(NSLocalizedString("raise_standard_strict_judgment", comment: "提高標準 (判定更嚴謹)"))
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
                            
                            Text(NSLocalizedString("lower_standard_loose_judgment", comment: "降低標準 (判定更寬鬆)"))
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
                    Text(NSLocalizedString("heart_rate_threshold_explanation", comment: "心率閾值說明"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text(NSLocalizedString("strict_detection_explanation", comment: "• 判定嚴謹：降低閾值使系統需要更低的心率才會判定入睡，減少誤判但可能延遲檢測"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("loose_detection_explanation", comment: "• 判定寬鬆：提高閾值使系統更容易判定入睡，可能更快檢測但增加誤判機率"))
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
        .navigationTitle(NSLocalizedString("heart_rate_threshold_title", comment: "心率閾值"))
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
                        Text(NSLocalizedString("strict", comment: "嚴謹"))
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text(NSLocalizedString("neutral", comment: "中性"))
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(NSLocalizedString("loose", comment: "寬鬆"))
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
                    Text(NSLocalizedString("sensitivity_adjustment_explanation", comment: "敏感度調整說明"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text(NSLocalizedString("strict_sensitivity_explanation", comment: "• 嚴謹：系統更嚴格判定睡眠狀態，降低誤判率但可能延遲檢測"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("loose_sensitivity_explanation", comment: "• 寬鬆：系統更寬鬆判定睡眠狀態，可能更快檢測但增加誤判率"))
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
        .navigationTitle(NSLocalizedString("detection_sensitivity_title", comment: "檢測敏感度"))
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
                    Text("\(NSLocalizedString("current_selection", comment: "當前選擇")): \(ageGroupTitle(currentAgeGroup))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                
                // 年齡組選項
                VStack(spacing: 10) {
                    ageGroupButtonLarge(title: NSLocalizedString("teenager_group", comment: "青少年 (< 18歲)"), description: NSLocalizedString("teenager_description", comment: "偏好更快入睡檢測，閾值設為87.5%"), ageGroup: .teen)
                    
                    ageGroupButtonLarge(title: NSLocalizedString("adult_group", comment: "成人 (18-60歲)"), description: NSLocalizedString("adult_description", comment: "標準檢測設定，閾值設為90%"), ageGroup: .adult)
                    
                    ageGroupButtonLarge(title: NSLocalizedString("senior_group", comment: "銀髮族 (> 60歲)"), description: NSLocalizedString("senior_description", comment: "更嚴謹的檢測，閾值設為93.5%"), ageGroup: .senior)
                }
                .padding(.horizontal)
                
                // 說明
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("age_group_settings_explanation", comment: "年齡組設置說明"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text(NSLocalizedString("age_group_explanation", comment: "選擇您的年齡組可以最佳化睡眠檢測閾值和確認時間。\n• 青少年：更敏感的檢測，確認時間為2分鐘\n• 成人：標準檢測，確認時間為3分鐘\n• 銀髮族：更嚴謹的檢測，確認時間為4分鐘"))
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
        .navigationTitle(NSLocalizedString("age_group_setting_title", comment: "年齡組設置"))
    }
    
    private func ageGroupTitle(_ ageGroup: AgeGroup) -> String {
        switch ageGroup {
        case .teen: return NSLocalizedString("teenager", comment: "青少年")
        case .adult: return NSLocalizedString("adult", comment: "成人")
        case .senior: return NSLocalizedString("senior", comment: "銀髮族")
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
                Text(NSLocalizedString("resting_heart_rate_label", comment: "靜息心率:"))
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
                Text(NSLocalizedString("sleep_threshold_label", comment: "睡眠閾值:"))
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
                    Text(NSLocalizedString("automatic_optimization_label", comment: "自動優化:"))
                        .foregroundColor(.gray)
                    Spacer()
                    
                    Text(NSLocalizedString("enabled", comment: "已啟用"))
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .medium))
                }
                
                HStack {
                    Text(NSLocalizedString("recent_optimization_label", comment: "最近優化:"))
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
                        Text(NSLocalizedString("enable_fragmented_sleep_mode", comment: "啟用碎片化睡眠模式"))
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
                    Text(NSLocalizedString("fragmented_sleep_explanation", comment: "碎片化睡眠模式說明"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text(NSLocalizedString("fragmented_sleep_description", comment: "如果您經常經歷睡眠碎片化（頻繁短暫醒來），啟用此模式可以提高睡眠檢測準確度。"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("changes_after_enabling", comment: "啟用後的變化："))
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                    
                    Text(NSLocalizedString("shorten_confirmation_time", comment: "• 縮短睡眠確認時間以捕捉短暫睡眠"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("optimize_micro_awakening", comment: "• 優化對微覺醒的處理"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("adjust_hr_monitoring", comment: "• 調整心率監測模式，適應快速變化"))
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
                    Text(NSLocalizedString("applicable_scenarios", comment: "適用情境"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    
                    Text(NSLocalizedString("light_sleeper", comment: "• 淺眠者：容易短暫醒來的睡眠習慣"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("environment_sensitive", comment: "• 環境敏感者：對環境聲音或光線敏感"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    
                    Text(NSLocalizedString("nap_difficulty", comment: "• 午休困難者：難以持續維持午休狀態"))
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
        .navigationTitle(NSLocalizedString("fragmented_sleep_title", comment: "碎片化睡眠"))
    }
}

// OnboardingView：首次啟動前導頁
struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var page: Int = 0
    @State private var scrolledToBottom: Bool = false
    @State private var showIntro: Bool = true
    @State private var introOpacity: Double = 1.0
    @State private var shareUsage: Bool = {
        if let saved = UserDefaults.standard.object(forKey: "shareUsage") as? Bool {
            return saved
        }
        return true // 預設勾選
    }()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // Intro overlay
            if showIntro {
                VStack(spacing: 8) {
                    Spacer()
                    Text(NSLocalizedString("welcome_to", comment: "歡迎使用"))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(NSLocalizedString("powernap", comment: "PowerNap"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .opacity(introOpacity)
                .onAppear {
                    // 4 秒停留後淡出 0.8 秒
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            introOpacity = 0
                        }
                        // 完成後移除視圖
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            showIntro = false
                        }
                    }
                }
            } else {
                // 主導覽頁 (3 頁)
                TabView(selection: $page) {
                    // Page 0 – 產品簡介
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(NSLocalizedString("what_is_powernap", comment: "什麼是 PowerNap？"))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 12)
                                Text(NSLocalizedString("powernap_description", comment: "PowerNap 是專為 Apple Watch 打造的科學小睡工具，結合心率與動作偵測..."))
                                    .foregroundColor(.white)
                                    .padding(.bottom, 30)
                                Button(action: { withAnimation { page = 1 } }) {
                                    Text(NSLocalizedString("next_page", comment: "下一頁"))
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(scrolledToBottom ? Color.blue : Color.gray)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(!scrolledToBottom)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                                Color.clear.frame(height: 1).id("bottom0")
                            }
                            .padding(.horizontal, 24)
                            .background(GeometryReader { geo in
                                Color.clear.onAppear { scrolledToBottom = false }
                                    .onChange(of: geo.frame(in: .named("scroll0")).maxY) { _, _ in
                                        DispatchQueue.main.async { scrolledToBottom = true }
                                    }
                            })
                        }
                        .coordinateSpace(name: "scroll0")
                    }
                    .tag(0)
                    // Page 1 – 使用說明 (原 Page 2)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(NSLocalizedString("how_to_use_correctly", comment: "如何正確使用？"))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 12)
                                Text(NSLocalizedString("how_to_use_description", comment: "PowerNap 會透過心率與動作資料自動判定入睡，初期準確率約 70–90%..."))
                                    .foregroundColor(.white)
                                    .padding(.bottom, 30)
                                Button(action: { withAnimation { page = 2 } }) {
                                    Text(NSLocalizedString("next_page", comment: "下一頁"))
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(scrolledToBottom ? Color.blue : Color.gray)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(!scrolledToBottom)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                                Color.clear.frame(height: 1).id("bottom1")
                            }
                            .padding(.horizontal, 24)
                            .background(GeometryReader { geo in
                                Color.clear.onAppear { scrolledToBottom = false }
                                    .onChange(of: geo.frame(in: .named("scroll1")).maxY) { _, _ in
                                        DispatchQueue.main.async { scrolledToBottom = true }
                                    }
                            })
                        }
                        .coordinateSpace(name: "scroll1")
                    }
                    .tag(1)
                    // Page 2 – 反饋教學
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(NSLocalizedString("how_to_report_accuracy", comment: "如何回報檢測準確度？"))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 12)

                                Text(NSLocalizedString("how_to_report_description", comment: "準確 － PowerNap 準時以震動喚醒且感受良好時..."))
                                    .foregroundColor(.white)
                                    .padding(.bottom, 30)

                                Toggle(isOn: $shareUsage) {
                                    Text(NSLocalizedString("share_anonymous_usage_data", comment: "分享匿名使用資料"))
                                        .foregroundColor(.white)
                                }
                                .toggleStyle(.switch)
                                .padding(.horizontal)

                                Text(NSLocalizedString("share_usage_detailed_description", comment: "分享匿名使用資料，協助我們持續優化偵測，讓更多人享有高品質小睡體驗。此設定不會上傳任何可識別個人或健康數據，您可隨時關閉。"))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal)

                                Button(action: {
                                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                    UserDefaults.standard.set(shareUsage, forKey: "shareUsage")
                                    requestInitialPermissions()
                                    withAnimation { showOnboarding = false }
                                }) {
                                    Text(NSLocalizedString("start_using", comment: "開始使用"))
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(scrolledToBottom ? Color.green : Color.gray)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(!scrolledToBottom)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)

                                Color.clear.frame(height: 1).id("bottom2")
                            }
                            .padding(.horizontal, 24)
                            .background(GeometryReader { geo in
                                Color.clear.onAppear { scrolledToBottom = false }
                                    .onChange(of: geo.frame(in: .named("scroll2")).maxY) { _, _ in
                                        DispatchQueue.main.async { scrolledToBottom = true }
                                    }
                            })
                        }
                        .coordinateSpace(name: "scroll2")
                    }
                    .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            }
        }
    }
    
    private func requestInitialPermissions() {
        // 通知權限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        // HealthKit 權限
        if HKHealthStore.isHealthDataAvailable() {
            let healthStore = HKHealthStore()
            let typesToRead: Set<HKObjectType> = [
                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
                HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
            ]
            let typesToShare: Set<HKSampleType> = [
                HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            ]
            healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { _, _ in }
        }
    }
}

#Preview {
    ContentView()
}

/// 匿名資料分享設定頁面
struct ShareUsageSettingView: View {
    @Binding var shareUsage: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Toggle(isOn: $shareUsage) {
                    Text(NSLocalizedString("share_anonymous_usage_data_toggle", comment: "分享匿名使用資料"))
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: .yellow))
                .padding()

                Text(NSLocalizedString("share_usage_detailed_description_toggle", comment: "分享匿名使用資料，協助我們持續優化偵測，讓更多人享有高品質小睡體驗。此設定不會上傳任何可識別個人或健康數據，您可隨時關閉。"))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
        }
        .background(Color.black)
        .navigationTitle(NSLocalizedString("data_sharing_title", comment: "資料分享"))
        .onChange(of: shareUsage) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "shareUsage")
        }
    }
}

// 說明主選單
struct InfoMenuView: View {
    var body: some View {
        List {
            NavigationLink(destination: InfoWhatView()) {
                Label(NSLocalizedString("what_is_powernap_title", comment: "什麼是 PowerNap？"), systemImage: "sparkles")
            }
            NavigationLink(destination: InfoHowView()) {
                Label(NSLocalizedString("how_to_use_correctly_title", comment: "如何正確使用？"), systemImage: "questionmark.circle")
            }
            NavigationLink(destination: InfoFeedbackView()) {
                Label(NSLocalizedString("how_to_report_accuracy_title", comment: "如何回報檢測準確度？"), systemImage: "hand.thumbsup")
            }
            NavigationLink(destination: InfoAuthorView()) {
                Label(NSLocalizedString("authors_message_title", comment: "作者的話"), systemImage: "person.crop.circle")
            }
        }
        .navigationTitle(NSLocalizedString("help_title", comment: "說明"))
        .background(Color.black)
    }
}

// 什麼是 PowerNap（完整版）
struct InfoWhatView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("what_is_powernap_title", comment: "什麼是 PowerNap？"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                Text(NSLocalizedString("what_is_powernap_full", comment: "PowerNap 是一款專為 Apple Watch 用戶打造的科學小睡應用..."))
                    .foregroundColor(.white)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.black)
        .navigationTitle(NSLocalizedString("what_is_powernap_title", comment: "什麼是 PowerNap？"))
    }
}

// 如何正確使用
struct InfoHowView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("how_to_use_correctly_title", comment: "如何正確使用？"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                Text(NSLocalizedString("how_to_use_correctly_full", comment: "PowerNap 會透過心率與動作資料自動判定入睡..."))
                    .foregroundColor(.white)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.black)
        .navigationTitle(NSLocalizedString("how_to_use_correctly_title", comment: "如何正確使用？"))
    }
}

// 如何回報檢測準確度
struct InfoFeedbackView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("how_to_report_accuracy_title", comment: "如何回報檢測準確度？"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                Text(NSLocalizedString("how_to_report_accuracy_full", comment: "準確 － PowerNap 準時以震動喚醒且感受良好時..."))
                    .foregroundColor(.white)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.black)
        .navigationTitle(NSLocalizedString("how_to_report_accuracy_title", comment: "如何回報檢測準確度？"))
    }
}

// 作者的話
struct InfoAuthorView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(NSLocalizedString("authors_message_title", comment: "作者的話"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 12)

                Text(NSLocalizedString("authors_message_content", comment: "身為一個曾經每晚醒來 12～15 次、長期受失眠困擾的人..."))
                    .font(.body)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.black)
        .navigationTitle(NSLocalizedString("authors_message_title", comment: "作者的話"))
    }
}
