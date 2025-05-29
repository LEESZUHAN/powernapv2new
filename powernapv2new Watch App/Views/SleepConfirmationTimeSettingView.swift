import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// 導入PowerNapViewModel
@preconcurrency import Foundation

/// 睡眠確認時間設定視圖
struct SleepConfirmationTimeSettingView: View {
    // MARK: - 屬性
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: PowerNapViewModel
    
    @State private var confirmationTimeSeconds: Int
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingResetAlert = false
    @State private var showingContinueAlert = false
    @State private var isLearningEnabled: Bool = true  // 新增：追蹤智慧學習狀態
    
    // 格式化時間顯示
    private var formattedTime: String {
        let minutes = confirmationTimeSeconds / 60
        let seconds = confirmationTimeSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - 初始化
    init(viewModel: PowerNapViewModel) {
        self.viewModel = viewModel
        // 從用戶配置獲取當前確認時間
        let currentTime = viewModel.currentUserProfile?.minDurationSeconds ?? 180
        self._confirmationTimeSeconds = State(initialValue: currentTime)
        
        // 初始化智慧學習狀態
        let isLearningDisabled = viewModel.currentUserProfile?.durationAdjustmentStopped ?? false
        self._isLearningEnabled = State(initialValue: !isLearningDisabled)
    }
    
    // MARK: - 視圖
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 8) {
                // 時間顯示 - 保持完整性
                VStack(spacing: 2) {
                    Text(formattedTime)
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    
                    Text("分:秒")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.top, 3)
                .padding(.bottom, 2)
                
                // 加減按鈕 - 使用較大的觸控區域
                HStack(spacing: 30) {
                    // 減號按鈕
                    Button(action: decreaseTime) {
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
                    Button(action: increaseTime) {
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
                .padding(.bottom, 8)
                
                // 保存按鈕
                Button(action: saveChanges) {
                    Text("保存設定")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 4)
                
                // 自動學習控制按鈕 - 移到保存按鈕下方形成三個主要按鈕
                VStack(spacing: 6) {
                    // 重置時間按鈕
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 18))
                            
                            Text("重置時間")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.2, opacity: 0.7))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 繼續智慧學習按鈕 - 改為開關式設計
                    Button(action: {
                        toggleSmartLearning()
                    }) {
                        HStack {
                            Image(systemName: isLearningEnabled ? "brain.head.profile.fill" : "brain.head.profile")
                                .foregroundColor(isLearningEnabled ? .green : .gray)
                                .font(.system(size: 18))
                            
                            Text(isLearningEnabled ? "智慧學習已開啟" : "智慧學習已關閉")
                                .foregroundColor(isLearningEnabled ? .white : .gray)
                                .font(.system(size: 16, weight: .medium))
                            
                            Spacer()
                            
                            Image(systemName: isLearningEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isLearningEnabled ? .green : .gray)
                                .font(.system(size: 18))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.2, opacity: 0.7))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // 調整提示和範圍提示 - 移到下方
                VStack(spacing: 2) {
                    Text("每次±10秒")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Text("範圍: 1-6分鐘")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.top, 8)
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                
                // 說明 - 保持在最下方
                VStack(alignment: .leading, spacing: 8) {
                    Text("關於確認時間")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("確認時間是系統判定您已進入睡眠所需的持續低心率時間。心率波動較大的用戶可能需要較長的確認時間(3-4分鐘)，而容易快速入睡的用戶可以設置較短的確認時間(1-2分鐘)。")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 10)
            }
            .padding(.horizontal)
        }
        .background(Color.black)
        .navigationTitle("睡眠確認時間")
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("設定已更新"),
                message: Text(alertMessage),
                dismissButton: .default(Text("確定")) {
                    self.presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .alert("重置確認時間", isPresented: $showingResetAlert) {
            Button("確定", role: .destructive) {
                resetTime()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這將重置為您年齡組的預設時間，並重新開始智慧學習。")
        }
        .alert("繼續智慧學習", isPresented: $showingContinueAlert) {
            Button("確定", role: .none) {
                continueSmartLearning()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這將基於當前的時間設定繼續智慧學習。")
        }
    }
    
    // MARK: - 方法
    private func decreaseTime() {
        // 每次減少10秒，但不低於60秒
        confirmationTimeSeconds = max(60, confirmationTimeSeconds - 10)
        
        // 觸發震動反饋
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
    
    private func increaseTime() {
        // 每次增加10秒，但不超過360秒
        confirmationTimeSeconds = min(360, confirmationTimeSeconds + 10)
        
        // 觸發震動反饋
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
    
    private func saveChanges() {
        if let currentProfile = viewModel.currentUserProfile {
            // 只有在值有變化時才更新
            if currentProfile.minDurationSeconds != confirmationTimeSeconds {
                // 使用ViewModel提供的方法更新確認時間，但不關閉智慧學習
                viewModel.updateSleepConfirmationTime(confirmationTimeSeconds, disableLearning: !isLearningEnabled)
                
                // 確保睡眠時間選擇器的值不小於新的確認時間
                viewModel.ensureValidNapDuration()
                
                // 觸發震動反饋
                #if os(watchOS)
                WKInterfaceDevice.current().play(.success)
                #endif
                
                alertMessage = "確認時間已設為 \(formattedTime)"
                showingAlert = true
            } else {
                // 值未變化，但可能需要更新學習狀態
                if isLearningEnabled != !currentProfile.durationAdjustmentStopped {
                    toggleSmartLearning(showAlert: false)
                }
                // 直接返回
                self.presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    private func resetTime() {
        // 調用ViewModel的重置方法
        viewModel.resetSleepConfirmationTime()
        
        // 更新UI顯示
        if let newTime = viewModel.currentUserProfile?.minDurationSeconds {
            confirmationTimeSeconds = newTime
            
            // 格式化時間字符串
            let minutes = newTime / 60
            let seconds = newTime % 60
            let timeString = String(format: "%d:%02d", minutes, seconds)
            
            // 設置提示信息
            alertMessage = "確認時間已重置為 \(timeString)"
            showingAlert = true
        }
        
        // 觸發震動反饋
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
    
    // 新增：切換智慧學習狀態
    private func toggleSmartLearning(showAlert: Bool = true) {
        // 切換狀態
        isLearningEnabled.toggle()
        
        // 根據新狀態調用相應方法
        if isLearningEnabled {
            // 開啟智慧學習
            viewModel.continueSleepLearning()
            
            if showAlert {
                // 設置提示信息
                alertMessage = "已開啟智慧學習，將基於現有設定 \(formattedTime) 繼續優化"
                showingAlert = true
            }
        } else {
            // 關閉智慧學習
            viewModel.disableSleepLearning()
            
            if showAlert {
                // 設置提示信息
                alertMessage = "已關閉智慧學習，系統將不再自動調整確認時間"
                showingAlert = true
            }
        }
        
        // 觸發震動反饋
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
    
    // 修改：保留原有方法作為相容性支持
    private func continueSmartLearning() {
        if !isLearningEnabled {
            isLearningEnabled = true
            viewModel.continueSleepLearning()
            
            // 設置提示信息
            alertMessage = "已開啟智慧學習，將基於現有設定 \(formattedTime) 繼續優化"
            showingAlert = true
            
            // 觸發震動反饋
            #if os(watchOS)
            WKInterfaceDevice.current().play(.success)
            #endif
        }
    }
} 