import Foundation
import os

/// 集中式計時器管理系統
/// 用於合併多個獨立計時器，優化CPU使用和電池消耗
public class TimerCoordinator {
    // MARK: - 單例模式
    public static let shared = TimerCoordinator()
    
    private init() {
        // 私有初始化方法，確保單例模式
        logger.info("初始化TimerCoordinator")
    }
    
    // MARK: - 屬性
    
    /// 主計時器
    private var mainTimer: Timer?
    
    /// 任務調度映射表 - [任務ID: (間隔, 上次執行時間, 任務, 預期執行次數, 實際執行次數)]
    private var tasks: [String: (interval: TimeInterval, lastRun: Date, task: () -> Void, expectedCalls: Int, actualCalls: Int)] = [:]
    
    /// 測試模式
    private var isInTestMode: Bool = false
    
    /// 測試任務列表
    private var testTasks: [String] = []
    
    /// 測試開始時間
    private var testStartTime: Date?
    
    /// 測試持續時間
    private var testDuration: TimeInterval = 10.0 // 10秒測試
    
    /// 記錄器
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "TimerCoordinator")
    
    // MARK: - 公開方法
    
    /// 啟動主計時器
    public func start() {
        guard mainTimer == nil else {
            logger.info("計時器已在運行中")
            return
        }
        
        mainTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAndRunTasks()
        }
        
        logger.info("主計時器已啟動")
    }
    
    /// 停止主計時器
    public func stop() {
        mainTimer?.invalidate()
        mainTimer = nil
        logger.info("主計時器已停止")
    }
    
    /// 添加任務
    /// - Parameters:
    ///   - id: 任務唯一標識符
    ///   - interval: 任務執行間隔（秒）
    ///   - task: 要執行的任務閉包
    public func addTask(id: String, interval: TimeInterval, task: @escaping () -> Void) {
        tasks[id] = (interval, Date(), task, 0, 0)
        logger.info("已添加任務: \(id), 間隔: \(interval)秒")
    }
    
    /// 移除任務
    /// - Parameter id: 要移除的任務ID
    public func removeTask(id: String) {
        tasks.removeValue(forKey: id)
        logger.info("已移除任務: \(id)")
    }
    
    /// 重置任務執行時間（立即執行一次）
    /// - Parameter id: 任務ID
    public func resetTaskTimer(id: String) {
        guard var taskInfo = tasks[id] else { return }
        taskInfo.lastRun = Date().addingTimeInterval(-taskInfo.interval)
        tasks[id] = taskInfo
    }
    
    /// 手動觸發所有任務立即執行一次
    public func triggerAllTasksNow() {
        let now = Date()
        for (id, taskInfo) in tasks {
            // 執行任務
            taskInfo.task()
            // 更新最後運行時間
            var updatedTaskInfo = taskInfo
            updatedTaskInfo.lastRun = now
            updatedTaskInfo.actualCalls += 1
            tasks[id] = updatedTaskInfo
            
            logger.info("手動觸發任務: \(id)")
        }
    }
    
    // MARK: - 測試方法
    
    /// 啟動計時器測試
    /// - Parameters:
    ///   - duration: 測試持續時間（秒）
    ///   - completion: 測試完成回調，返回測試結果
    public func startTimerTest(duration: TimeInterval = 10.0, completion: @escaping ([String: Bool]) -> Void) {
        guard !isInTestMode else {
            logger.warning("測試已在進行中")
            return
        }
        
        // 進入測試模式
        isInTestMode = true
        testStartTime = Date()
        testDuration = duration
        testTasks = Array(tasks.keys)
        
        // 重置所有任務計數
        for (id, taskInfo) in tasks {
            var updatedTaskInfo = taskInfo
            updatedTaskInfo.expectedCalls = Int(ceil(duration / taskInfo.interval))
            updatedTaskInfo.actualCalls = 0
            tasks[id] = updatedTaskInfo
            logger.info("測試任務: \(id), 預期執行次數: \(updatedTaskInfo.expectedCalls)")
        }
        
        // 確保主計時器運行中
        if mainTimer == nil {
            start()
        }
        
        // 設置測試完成計時器
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.isInTestMode else { return }
            
            // 計算測試結果
            var testResults: [String: Bool] = [:]
            for (id, taskInfo) in self.tasks {
                // 任務執行次數是否達到預期（允許±1次誤差）
                let success = abs(taskInfo.actualCalls - taskInfo.expectedCalls) <= 1
                testResults[id] = success
                
                self.logger.info("測試結果: \(id), 預期/實際: \(taskInfo.expectedCalls)/\(taskInfo.actualCalls), \(success ? "通過" : "失敗")")
            }
            
            // 退出測試模式
            self.isInTestMode = false
            self.testStartTime = nil
            
            // 回調測試結果
            completion(testResults)
        }
    }
    
    /// 獲取測試進度
    /// - Returns: 測試進度，範圍0-1
    public func getTestProgress() -> Double {
        guard isInTestMode, let startTime = testStartTime else { return 0 }
        let elapsedTime = Date().timeIntervalSince(startTime)
        return min(1.0, elapsedTime / testDuration)
    }
    
    /// 檢查測試是否正在進行
    public var isTestingInProgress: Bool {
        return isInTestMode
    }
    
    // MARK: - 私有方法
    
    /// 檢查並執行需要運行的任務
    private func checkAndRunTasks() {
        let now = Date()
        for (id, taskInfo) in tasks {
            if now.timeIntervalSince(taskInfo.lastRun) >= taskInfo.interval {
                // 執行任務
                taskInfo.task()
                
                // 更新最後運行時間和執行計數
                var updatedTaskInfo = taskInfo
                updatedTaskInfo.lastRun = now
                if isInTestMode {
                    updatedTaskInfo.actualCalls += 1
                }
                tasks[id] = updatedTaskInfo
                
                if isInTestMode {
                    logger.info("測試期間執行任務: \(id), 當前計數: \(updatedTaskInfo.actualCalls)")
                }
            }
        }
    }
} 