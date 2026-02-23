import Foundation

enum PingOutputParser {
    private static let pattern = /time=(\d+\.?\d*)\s*ms/

    static func parseLatency(from output: String) -> Double? {
        guard let match = output.firstMatch(of: pattern) else { return nil }
        return Double(match.1)
    }
}
