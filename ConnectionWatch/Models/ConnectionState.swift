import SwiftUI

enum ConnectionState: String {
    case good
    case degraded
    case disconnected
    case paused

    var color: Color {
        switch self {
        case .good: .green
        case .degraded: .yellow
        case .disconnected: .red
        case .paused: .gray
        }
    }

    var label: String {
        switch self {
        case .good: "Connected"
        case .degraded: "Degraded"
        case .disconnected: "Disconnected"
        case .paused: "Paused"
        }
    }

    var notificationTitle: String {
        switch self {
        case .good: "Connection Restored"
        case .degraded: "Connection Degraded"
        case .disconnected: "Connection Lost"
        case .paused: "Monitoring Paused"
        }
    }

    var notificationBody: String {
        switch self {
        case .good: "Your internet connection is healthy."
        case .degraded: "Your internet connection is slow or unreliable."
        case .disconnected: "Your internet connection appears to be down."
        case .paused: "Network monitoring is currently paused."
        }
    }
}
