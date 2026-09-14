import SwiftUI

@main
struct ConnectionWatchApp: App {
    @State private var viewModel = StatusViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(viewModel: viewModel)
        } label: {
            StatusItemView(
                state: viewModel.currentState,
                score: viewModel.health.score,
                pingLatency: viewModel.latestPingLatency,
                httpLatency: viewModel.latestHTTPLatency
            )
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: PopoverMetrics.width, height: PopoverMetrics.height)
        .onChange(of: viewModel.currentState) { }
    }
}
