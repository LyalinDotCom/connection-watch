import SwiftUI

@main
struct ConnectionWatchApp: App {
    @State private var viewModel = StatusViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(viewModel: viewModel)
        } label: {
            StatusItemView(state: viewModel.currentState)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 320, height: 400)
        .onChange(of: viewModel.currentState) { }
    }

    init() {
        // Delay start slightly to let the app set up
        DispatchQueue.main.async { [self] in
            viewModel.start()
        }
    }
}
