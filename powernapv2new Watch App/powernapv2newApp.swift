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
        requestHealthKitPermissions()
        requestNotificationPermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
