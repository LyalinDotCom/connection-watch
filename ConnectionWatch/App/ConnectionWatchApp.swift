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
                pingLatency: viewModel.latestPingLatency
            )
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 380, height: 470)
        .onChange(of: viewModel.currentState) { }
    }

    init() {
        // Delay start slightly to let the app set up
        DispatchQueue.main.async { [self] in
            viewModel.start()
        }
    }
}
