import Foundation

actor PingService {
    func ping(target: String = "1.1.1.1", count: Int = 3, timeoutMs: Int = 1000) async -> PingResult {
        let timestamp = Date()

        do {
            let output = try await runPing(target: target, count: count, timeoutMs: timeoutMs)
            if let summary = PingOutputParser.parseSummary(from: output) {
                return PingResult(
                    timestamp: timestamp,
                    latency: summary.avgLatency,
                    jitter: summary.jitter,
                    packetLossPercent: summary.packetLossPercent ?? (summary.avgLatency == nil ? 100.0 : 0.0),
                    endpoint: target,
                    probeType: .ping
                )
            }
            let latency = PingOutputParser.parseLatency(from: output)
            return PingResult(
                timestamp: timestamp,
                latency: latency,
                jitter: nil,
                packetLossPercent: latency == nil ? 100.0 : 0.0,
                endpoint: target,
                probeType: .ping
            )
        } catch {
            return PingResult(
                timestamp: timestamp,
                latency: nil,
                jitter: nil,
                packetLossPercent: 100.0,
                endpoint: target,
                probeType: .ping
            )
        }
    }

    private func runPing(target: String, count: Int, timeoutMs: Int) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // Send rapid burst of `count` packets with 200ms spacing and `timeoutMs` per-packet timeout
        process.arguments = ["-c", "\(count)", "-i", "0.2", "-W", "\(timeoutMs)", target]
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                process.terminationHandler = { _ in
                    let fileHandle = pipe.fileHandleForReading
                    let data = fileHandle.readDataToEndOfFile()
                    try? fileHandle.close()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
