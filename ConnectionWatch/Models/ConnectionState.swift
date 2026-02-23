import SwiftUI

enum ConnectionState: String {
    case good
    case degraded
    case disconnected

    var color: Color {
        switch self {
        case .good: .green
        case .degraded: .yellow
        case .disconnected: .red
        }
    }

    var label: String {
        switch self {
        case .good: "Connected"
        case .degraded: "Degraded"
        case .disconnected: "Disconnected"
        }
    }

    var notificationTitle: String {
        switch self {
        case .good: "Connection Restored"
        case .degraded: "Connection Degraded"
        case .disconnected: "Connection Lost"
        }
    }

    var notificationBody: String {
        switch self {
        case .good: "Your internet connection is healthy."
        case .degraded: "Your internet connection has high latency."
        case .disconnected: "Your internet connection appears to be down."
        }
    }
}
