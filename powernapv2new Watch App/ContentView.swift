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
    
    // 增加用於分頁控制的狀態
    @State private var selectedTab = 0
    
    // 增加用於查看日誌的狀態
    @State private var logFiles: [URL] = []
    @State private var selectedLogFile: URL?
    @State private var logContent: String = ""
    
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
            
            // 添加數據記錄頁面
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                dataLogsView
            }
            .tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .onAppear {
            loadLogFiles()
        }
    }
    
    // 準備狀態視圖
    private var preparingView: some View {
        GeometryReader { geometry in
            VStack {
                // 休息時間垂直間距改為0%
                
                Text("休息時間")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.bottom, -5)
                
                // 時間選擇框 - 移除外部自定義邊框
                Picker("", selection: $viewModel.napDuration) {
                    ForEach(1...30, id: \.self) { minutes in
                        Text("\(minutes)").tag(Double(minutes * 60))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: geometry.size.height * 0.35)
                .clipped()
                .padding(.horizontal, geometry.size.width * 0.1)
                
                Text("分鐘")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, -5)
                
                // 按鈕位置往上移，使用Spacer自動調整
                Spacer()
                
                // 開始按鈕
                Button(action: {
                    viewModel.startNap()
                }) {
                    Text("開始休息")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: geometry.size.width * 0.6, height: 44)
                        .background(Color.blue)
                        .cornerRadius(22)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, geometry.size.height * 0.05)  // 底部間距改為5%
            }
            .padding()
        }
    }
    
    // 測試功能頁面視圖 - 增加顯示心率、靜止心率和運動狀況
    private var testFunctionsView: some View {
        VStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 20) {
                        Text("開發測試功能")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.top, 10)
                            .id("top") // 添加ID用於滾動參考點
                        
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
                        
                        Spacer().frame(height: 20)
                        
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
                    }
                    .padding(.bottom, 20)
                }
                // 完全移除任何引用 contentOffset 的修飾符
                .onAppear {
                    // 如需初始滾動定位可以在這裡添加
                    // scrollProxy.scrollTo("top", anchor: .top)
                }
            }
        }
        .padding(.top, 10)
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
            
            // 取消按鈕 - 往上移
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
            .padding(.bottom, 30)
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
        .padding(.top, 10)
    }
    
    // 日誌文件列表視圖
    private var logFilesListView: some View {
        VStack {
            Text("睡眠數據記錄")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 5)
            
            ScrollView {
                VStack(spacing: 10) {
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
                                    Text(fileURL.lastPathComponent
                                        .replacingOccurrences(of: "powernap_session_", with: "")
                                        .replacingOccurrences(of: ".csv", with: ""))
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    
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
                
                Text(selectedLogFile?.lastPathComponent
                    .replacingOccurrences(of: "powernap_session_", with: "")
                    .replacingOccurrences(of: ".csv", with: "") ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal)
            .padding(.bottom, 5)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if logContent.isEmpty {
                        Text("載入中...")
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    } else {
                        Text(formatLogSummary(logContent))
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    }
                }
                .padding()
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
        var header = lines.first ?? ""
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
}

#Preview {
    ContentView()
}
