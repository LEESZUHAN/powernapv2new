import Foundation
import os

/// 中央計時器協調器，用於統一管理應用程序中的所有計時器任務
class TimerCoordinator {
    // MARK: - 單例模式
    static let shared = TimerCoordinator()
    
    // 私有初始化方法確保單例模式
    private init() {
        logger.info("TimerCoordinator已初始化")
    }
    
    // MARK: - 屬性
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "TimerCoordinator")
    
    // 主計時器
    private var mainTimer: Timer?
    
    // 任務調度映射表，存儲各種計時任務及其相關信息
    private var tasks: [String: TaskInfo] = [:]
    
    // 追蹤上次執行時間的字典
    private var lastExecutionTimes: [String: Date] = [:]
    
    // 任務計數器，用於調試和測試
    private var executionCounts: [String: Int] = [:]
    
    // 任務調度狀態
    private(set) var isRunning: Bool = false
    
    // 用於測試的任務狀態發布者
    var taskStatusCallback: (([String: TaskStatus]) -> Void)?
    
    // MARK: - 任務類型與狀態定義
    
    /// 任務信息結構體
    struct TaskInfo {
        let interval: TimeInterval  // 任務執行間隔（秒）
        let task: () -> Void        // 任務執行閉包
        let priority: TaskPriority  // 任務優先級
        var isEnabled: Bool = true  // 任務是否啟用
    }
    
    /// 任務優先級枚舉
    enum TaskPriority: Int, Comparable {
        case high = 0
        case normal = 1
        case low = 2
        
        static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    /// 任務狀態結構體（用於測試和監控）
    struct TaskStatus {
        let id: String
        let interval: TimeInterval
        let lastExecution: Date?
        let executionCount: Int
        let isEnabled: Bool
        let priority: TaskPriority
    }
    
    // MARK: - 公共方法
    
    /// 啟動主計時器
    func start() {
        guard !isRunning else {
            logger.warning("TimerCoordinator已在運行中")
            return
        }
        
        mainTimer?.invalidate()
        mainTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAndRunTasks()
        }
        
        isRunning = true
        logger.info("TimerCoordinator已啟動主計時器")
    }
    
    /// 停止主計時器
    func stop() {
        mainTimer?.invalidate()
        mainTimer = nil
        isRunning = false
        logger.info("TimerCoordinator已停止主計時器")
    }
    
    /// 添加任務
    func addTask(id: String, interval: TimeInterval, priority: TaskPriority = .normal, task: @escaping () -> Void) {
        tasks[id] = TaskInfo(interval: interval, task: task, priority: priority)
        lastExecutionTimes[id] = Date() // 初始化執行時間為當前時間
        executionCounts[id] = 0
        logger.info("添加任務: \(id), 間隔: \(interval)秒, 優先級: \(priority)")
    }
    
    /// 移除任務
    func removeTask(id: String) {
        tasks.removeValue(forKey: id)
        lastExecutionTimes.removeValue(forKey: id)
        executionCounts.removeValue(forKey: id)
        logger.info("移除任務: \(id)")
    }
    
    /// 啟用任務
    func enableTask(id: String) {
        if var taskInfo = tasks[id] {
            taskInfo.isEnabled = true
            tasks[id] = taskInfo
            logger.info("啟用任務: \(id)")
        }
    }
    
    /// 禁用任務
    func disableTask(id: String) {
        if var taskInfo = tasks[id] {
            taskInfo.isEnabled = false
            tasks[id] = taskInfo
            logger.info("禁用任務: \(id)")
        }
    }
    
    /// 立即執行特定任務（不影響其常規調度）
    func executeTaskNow(id: String) {
        guard let taskInfo = tasks[id] else {
            logger.warning("嘗試執行不存在的任務: \(id)")
            return
        }
        
        logger.info("立即執行任務: \(id)")
        taskInfo.task()
    }
    
    /// 重置任務執行計時（相當於任務剛剛執行過）
    func resetTaskTimer(id: String) {
        lastExecutionTimes[id] = Date()
        logger.info("重置任務計時: \(id)")
    }
    
    /// 獲取所有任務的執行狀態（用於測試和監控）
    func getAllTaskStatus() -> [String: TaskStatus] {
        var statuses: [String: TaskStatus] = [:]
        
        for (id, taskInfo) in tasks {
            statuses[id] = TaskStatus(
                id: id,
                interval: taskInfo.interval,
                lastExecution: lastExecutionTimes[id],
                executionCount: executionCounts[id] ?? 0,
                isEnabled: taskInfo.isEnabled,
                priority: taskInfo.priority
            )
        }
        
        return statuses
    }
    
    // MARK: - 私有方法
    
    /// 檢查並執行需要運行的任務
    private func checkAndRunTasks() {
        let now = Date()
        
        // 收集需要執行的任務，按優先級排序
        var tasksToRun: [(id: String, task: () -> Void)] = []
        
        for (id, taskInfo) in tasks {
            // 只處理啟用的任務
            guard taskInfo.isEnabled else { continue }
            
            // 檢查是否達到執行間隔
            if let lastRun = lastExecutionTimes[id], now.timeIntervalSince(lastRun) >= taskInfo.interval {
                tasksToRun.append((id: id, task: taskInfo.task))
                lastExecutionTimes[id] = now
                executionCounts[id] = (executionCounts[id] ?? 0) + 1
            }
        }
        
        // 按優先級排序任務
        tasksToRun.sort { (task1, task2) in
            let priority1 = tasks[task1.id]?.priority ?? .normal
            let priority2 = tasks[task2.id]?.priority ?? .normal
            return priority1 < priority2 // 高優先級先執行
        }
        
        // 執行任務
        for (id, task) in tasksToRun {
            // 將任務分派到適當的隊列
            if id.contains("heartRate") || id.contains("motion") {
                // 心率和動作分析任務放入後台隊列
                DispatchQueue.global(qos: .utility).async {
                    task()
                }
            } else {
                // UI更新相關任務在主隊列執行
                DispatchQueue.main.async {
                    task()
                }
            }
            
            logger.debug("執行任務: \(id), 執行次數: \(self.executionCounts[id] ?? 0)")
        }
        
        // 如果設置了回調，發送任務狀態
        if let callback = taskStatusCallback {
            callback(getAllTaskStatus())
        }
    }
} 