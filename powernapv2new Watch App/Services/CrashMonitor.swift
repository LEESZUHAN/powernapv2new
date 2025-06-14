import Foundation
#if !os(watchOS)
import MetricKit
#endif

/// 監聽 MetricsKit Crash 診斷並上傳至 CloudKit
#if !os(watchOS)
final class CrashMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashMonitor()
    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
        print("[CrashMonitor] Registered MXMetricManager subscriber")
    }
    deinit {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber
    /// 收到診斷（Crash / Hang / CPU 等）
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // 只處理 Crash 診斷
            guard let crashes = payload.crashDiagnostics, !crashes.isEmpty else { continue }
            let appVersion = payload.applicationVersion
            let ts = ISO8601DateFormatter().string(from: payload.timeStampEnd)
            
            for crash in crashes.prefix(3) { // 每次僅取前 3 筆，避免大量上傳
                var params: [String: String] = [
                    "appVersion": appVersion,
                    "timestamp": ts,
                    "signal": crash.signal,
                    "terminationReason": "\(crash.terminationReason.rawValue)"
                ]
                // 呼叫堆疊僅取第一行，避免超過欄位大小
                if let firstFrame = crash.callStackTree.callStackFrames.first {
                    params["firstFrame"] = firstFrame.symbol ?? "unknown"
                }
                if UserDefaults.standard.bool(forKey: "shareUsage") {
                    CloudKitLogger.shared.save(name: "crash_log", params: params)
                }
            }
        }
    }

    /// Metrics payload，目前未使用
    func didReceive(_ payloads: [MXMetricPayload]) {
        // 可擴充收集耗電 / 內存指標
    }
}
#endif 