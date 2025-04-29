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
    }
    
    // 準備狀態視圖
    private var preparingView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // 時間選擇框
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green, lineWidth: 2)
                    .frame(height: 60)
                
                Picker("休息時間", selection: $viewModel.napDuration) {
                    Text("5:00").tag(5 * 60.0)
                    Text("10:00").tag(10 * 60.0)
                    Text("15:00").tag(15 * 60.0)
                    Text("20:00").tag(20 * 60.0)
                    Text("25:00").tag(25 * 60.0)
                    Text("30:00").tag(30 * 60.0)
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .clipped()
            }
            
            Text("分鐘")
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
            
            // 開始按鈕
            Button(action: {
                viewModel.startNap()
            }) {
                Text("開始休息")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 160, height: 44)
                    .background(Color.blue)
                    .cornerRadius(22)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 測試鬧鈴按鈕 - 放在主視圖底部，顏色更醒目
            Button(action: {
                // 直接調用通知管理器發送通知
                NotificationManager.shared.sendWakeupNotification()
            }) {
                Text("測試鬧鈴")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .cornerRadius(22)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .padding()
    }
    
    // 監測狀態視圖
    private var monitoringView: some View {
        VStack(spacing: 40) {
            Text("監測中")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white)
            
            // 已移除心電圖，替換為簡單文字
            Text("等待入睡...")
                .font(.system(size: 22))
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
