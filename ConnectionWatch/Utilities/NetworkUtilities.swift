import Foundation

extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self <= 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

final class URLSessionMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMetrics: URLSessionTaskMetrics?

    var collectedMetrics: URLSessionTaskMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return storedMetrics
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        storedMetrics = metrics
        lock.unlock()
    }
}
