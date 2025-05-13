import Foundation
import os

/// 計時器協調器
/// 負責集中管理和調度應用中的所有計時器任務
public class TimerCoordinator {
    // MARK: - 單例模式
    public static let shared = TimerCoordinator()
    
    // MARK: - 公開屬性
    
    /// 是否已啟動
    private(set) var isRunning: Bool = false
    
    // MARK: - 私有屬性
    
    /// 主計時器
    private var mainTimer: Timer?
    
    /// 任務字典 - 存儲所有註冊的任務
    private var tasks: [String: TaskInfo] = [:]
    
    /// 任務執行統計 - 用於診斷
    private var taskExecStats: [String: TaskExecStats] = [:]
    
    /// 日誌記錄器
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "TimerCoordinator")
    
    // MARK: - 初始化
    private init() {
        // 私有初始化，確保單例模式
    }
    
    // MARK: - 任務結構定義
    
    /// 任務信息結構
    struct TaskInfo {
        /// 任務ID
        let id: String
        /// 任務執行間隔（秒）
        let interval: TimeInterval
        /// 上次執行時間
        var lastRun: Date
        /// 任務執行回調
        let task: () -> Void
        /// 優先級
        let priority: TaskPriority
        
        /// 是否需要執行
        func shouldRunNow(at currentTime: Date) -> Bool {
            return currentTime.timeIntervalSince(lastRun) >= interval
        }
    }
    
    /// 任務優先級枚舉
    public enum TaskPriority: Int, Comparable {
        case high = 0
        case medium = 1
        case low = 2
        
        public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    /// 任務執行統計
    struct TaskExecStats {
        /// 總執行次數
        var totalExecutions: Int = 0
        /// 平均執行間隔
        var avgInterval: TimeInterval = 0
        /// 上次執行時間
        var lastExecTime: Date = Date()
        /// 執行間隔樣本
        var intervalSamples: [TimeInterval] = []
        
        mutating func recordExecution() {
            let now = Date()
            let interval = now.timeIntervalSince(lastExecTime)
            
            totalExecutions += 1
            
            // 記錄間隔樣本（最多保存20個樣本）
            if intervalSamples.count >= 20 {
                intervalSamples.removeFirst()
            }
            intervalSamples.append(interval)
            
            // 計算平均間隔
            avgInterval = intervalSamples.reduce(0, +) / Double(intervalSamples.count)
            
            // 更新上次執行時間
            lastExecTime = now
        }
    }
    
    // MARK: - 公開方法
    
    /// 啟動主計時器
    public func start() {
        guard !isRunning else { return }
        
        mainTimer?.invalidate()
        mainTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAndRunTasks()
        }
        
        isRunning = true
        logger.info("計時器協調器已啟動")
    }
    
    /// 停止主計時器
    public func stop() {
        guard isRunning else { return }
        
        mainTimer?.invalidate()
        mainTimer = nil
        isRunning = false
        
        logger.info("計時器協調器已停止")
    }
    
    /// 添加任務
    public func addTask(id: String, interval: TimeInterval, priority: TaskPriority = .medium, task: @escaping () -> Void) {
        tasks[id] = TaskInfo(
            id: id,
            interval: interval,
            lastRun: Date(),
            task: task,
            priority: priority
        )
        
        // 初始化任務統計
        taskExecStats[id] = TaskExecStats()
        
        logger.info("已添加任務: ID=\(id), 間隔=\(interval)秒, 優先級=\(priority)")
        
        // 確保計時器在添加第一個任務時啟動
        if !isRunning && tasks.count == 1 {
            start()
        }
    }
    
    /// 移除任務
    public func removeTask(id: String) {
        tasks.removeValue(forKey: id)
        taskExecStats.removeValue(forKey: id)
        
        logger.info("已移除任務: ID=\(id)")
        
        // 如果沒有任務，停止計時器
        if tasks.isEmpty {
            stop()
        }
    }
    
    /// 獲取任務執行統計
    public func getTaskStats() -> [String: (executions: Int, avgInterval: TimeInterval)] {
        var result: [String: (executions: Int, avgInterval: TimeInterval)] = [:]
        
        for (id, stats) in taskExecStats {
            result[id] = (stats.totalExecutions, stats.avgInterval)
        }
        
        return result
    }
    
    /// 獲取任務數量
    public func getTaskCount() -> Int {
        return tasks.count
    }
    
    /// 任務測試 - 檢查所有任務是否按照預期間隔執行
    public func runTaskTest() -> [String: String] {
        var testResults: [String: String] = [:]
        
        // 檢查計時器是否運行
        if !isRunning {
            testResults["main_timer"] = "失敗: 主計時器未運行"
            return testResults
        }
        
        // 檢查每個任務的執行情況
        for (id, stats) in taskExecStats {
            guard let taskInfo = tasks[id] else {
                testResults[id] = "錯誤: 找不到任務信息"
                continue
            }
            
            // 對於新添加但尚未執行的任務
            if stats.totalExecutions == 0 {
                testResults[id] = "等待中: 任務尚未執行"
                continue
            }
            
            // 檢查平均執行間隔是否接近設定值
            let interval = taskInfo.interval
            let avgInterval = stats.avgInterval
            let deviation = abs(avgInterval - interval) / interval
            
            if deviation <= 0.15 { // 允許15%的偏差
                testResults[id] = "正常: 預期間隔=\(interval)秒, 實際間隔=\(String(format: "%.2f", avgInterval))秒"
            } else {
                testResults[id] = "異常: 預期間隔=\(interval)秒, 實際間隔=\(String(format: "%.2f", avgInterval))秒, 偏差=\(String(format: "%.1f", deviation * 100))%"
            }
        }
        
        // 如果沒有任務
        if taskExecStats.isEmpty {
            testResults["no_tasks"] = "警告: 沒有註冊任務"
        }
        
        // 記錄測試結果
        logger.info("計時器測試結果: \(testResults)")
        
        return testResults
    }
    
    // MARK: - 私有方法
    
    /// 檢查並執行需要運行的任務
    private func checkAndRunTasks() {
        let now = Date()
        
        // 將任務按優先級排序
        let sortedTasks = tasks.values.sorted { $0.priority < $1.priority }
        
        for var taskInfo in sortedTasks {
            if taskInfo.shouldRunNow(at: now) {
                // 記錄執行前的時間
                let startTime = Date()
                
                // 執行任務
                taskInfo.task()
                
                // 更新任務的最後執行時間
                tasks[taskInfo.id]?.lastRun = now
                
                // 更新統計信息
                taskExecStats[taskInfo.id]?.recordExecution()
                
                // 記錄任務執行時間
                let executionTime = Date().timeIntervalSince(startTime)
                if executionTime > 0.1 { // 如果執行時間超過100毫秒，記錄警告
                    logger.warning("任務執行時間較長: ID=\(taskInfo.id), 時間=\(executionTime)秒")
                }
            }
        }
    }
} 