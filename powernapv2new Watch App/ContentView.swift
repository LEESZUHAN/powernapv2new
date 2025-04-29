//
//  ContentView.swift
//  powernapv2new Watch App
//
//  Created by michaellee on 4/27/25.
//

import SwiftUI

// 導入PowerNapViewModel
@preconcurrency import Foundation

struct HeartRateWaveView: View {
    @State private var phase: CGFloat = 0
    
    // 動畫定時器
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    // 心電圖路徑點
    private let points: [CGPoint] = [
        CGPoint(x: 0, y: 0.5),
        CGPoint(x: 0.1, y: 0.5),
        CGPoint(x: 0.15, y: 0.4),
        CGPoint(x: 0.2, y: 0.5),
        CGPoint(x: 0.25, y: 1.0),
        CGPoint(x: 0.3, y: 0.1),
        CGPoint(x: 0.35, y: 0.5),
        CGPoint(x: 0.4, y: 0.5),
        CGPoint(x: 0.45, y: 0.5),
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.55, y: 0.5),
        CGPoint(x: 0.6, y: 0.4),
        CGPoint(x: 0.65, y: 0.5),
        CGPoint(x: 0.7, y: 0.9),
        CGPoint(x: 0.75, y: 0.1),
        CGPoint(x: 0.8, y: 0.5),
        CGPoint(x: 0.85, y: 0.5),
        CGPoint(x: 0.9, y: 0.5),
        CGPoint(x: 1.0, y: 0.5)
    ]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // 起始點
                let startPoint = CGPoint(
                    x: self.adjustedX(points[0].x, phase: phase, width: geometry.size.width),
                    y: points[0].y * geometry.size.height
                )
                path.move(to: startPoint)
                
                // 繪製每個點
                for i in 1..<points.count {
                    let point = CGPoint(
                        x: self.adjustedX(points[i].x, phase: phase, width: geometry.size.width),
                        y: points[i].y * geometry.size.height
                    )
                    path.addLine(to: point)
                }
            }
            .stroke(Color.white, lineWidth: 2)
        }
        .frame(height: 50)
        .onReceive(timer) { _ in
            // 更新相位以創建動畫效果
            withAnimation(.linear(duration: 0.1)) {
                phase += 0.03
                if phase > 1 {
                    phase = 0
                }
            }
        }
    }
    
    // 調整x座標以創建滾動效果
    private func adjustedX(_ x: CGFloat, phase: CGFloat, width: CGFloat) -> CGFloat {
        let adjustedX = x - phase
        // 處理循環
        if adjustedX < 0 {
            return width + adjustedX
        }
        return adjustedX * width
    }
}

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
            
            Spacer()
        }
        .padding()
    }
    
    // 監測狀態視圖
    private var monitoringView: some View {
        VStack(spacing: 25) {
            Text("監測中")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
            
            // 心電圖動畫
            HeartRateWaveView()
                .frame(height: 60)
            
            Text("等待入睡...")
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
                    .frame(width: 100, height: 44)
                    .background(Color.red)
                    .cornerRadius(22)
            }
            .buttonStyle(PlainButtonStyle())
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
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
            
            // 取消按鈕
            Button(action: {
                viewModel.stopNap()
            }) {
                Text("取消")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 100, height: 44)
                    .background(Color.red)
                    .cornerRadius(22)
            }
            .buttonStyle(PlainButtonStyle())
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
