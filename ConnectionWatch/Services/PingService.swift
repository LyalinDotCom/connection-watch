import Foundation

actor PingService {
    func ping(target: String = "1.1.1.1", timeout: Int = 2000) async -> PingResult {
        let timestamp = Date()

        do {
            let output = try await runPing(target: target, timeout: timeout)
            let latency = PingOutputParser.parseLatency(from: output)
            return PingResult(timestamp: timestamp, latency: latency, endpoint: target, probeType: .ping)
        } catch {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: target, probeType: .ping)
        }
    }

    private func runPing(target: String, timeout: Int) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "\(timeout)", target]
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
            process.terminate()
        }
    }
}
