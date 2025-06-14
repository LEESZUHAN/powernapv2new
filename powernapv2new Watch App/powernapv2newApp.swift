//
//  powernapv2newApp.swift
//  powernapv2new Watch App
//
//  Created by michaellee on 4/27/25.
//

import SwiftUI
import HealthKit
import UserNotifications

@main
struct powernapv2new_Watch_AppApp: App {
    // 確保已經請求了HealthKit權限和通知權限
    init() {
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            requestHealthKitPermissions()
            requestNotificationPermissions()
        }
        // 產生並保存 pseudonymous installationId，供 CloudKitLogger 使用
        let defaults = UserDefaults.standard
        let installKey = "installationId"
        if defaults.string(forKey: installKey) == nil {
            defaults.set(UUID().uuidString, forKey: installKey)
        }
        // 若尚未設置 shareUsage，預設開啟（可於設定中關閉）
        if defaults.object(forKey: "shareUsage") == nil {
            defaults.set(true, forKey: "shareUsage")
        }
        
        // Telemetry 功能已移除，僅保留本地 ID
        
        // 測試 CloudKit 連接（延遲執行避免阻塞啟動）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            TelemetryLogger.shared.testCloudKitConnection()
        }
        
        // 測試 CloudKit 匯出（延遲執行）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            TelemetryLogger.shared.testExportAllRecords()
        }
        
        // 啟動 CrashMonitor（MetricsKit Crash 收集）
        #if !os(watchOS)
        _ = CrashMonitor.shared
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
    
    // 請求HealthKit權限
    private func requestHealthKitPermissions() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit在此設備上不可用")
            return
        }
        
        // 需要讀取的類型
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        ]
        
        // 需要共享的類型
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        let healthStore = HKHealthStore()
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit授權請求錯誤: \(error.localizedDescription)")
            } else if success {
                print("HealthKit授權成功")
            } else {
                print("HealthKit授權被拒絕")
            }
        }
    }
    
    // 請求通知權限
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { success, error in
            if let error = error {
                print("通知授權請求錯誤: \(error.localizedDescription)")
            } else if success {
                print("通知授權成功")
            } else {
                print("通知授權被拒絕")
            }
        }
    }
}
