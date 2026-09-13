import SwiftUI

struct StatusItemView: View {
    let state: ConnectionState
    var score: Int? = nil
    var pingLatency: Double? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: statusImage)
            if state == .paused {
                Text("Paused")
                    .font(.system(size: 11, weight: .medium))
            } else if let pingLatency {
                Text(String(format: "%.0fms", pingLatency))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            } else if let score {
                Text("\(score)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    private var statusImage: NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            NSColor(self.state.color).setFill()
            circle.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
