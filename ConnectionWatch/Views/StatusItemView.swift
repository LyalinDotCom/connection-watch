import SwiftUI

struct StatusItemView: View {
    let state: ConnectionState

    var body: some View {
        Image(nsImage: statusImage)
    }

    private var statusImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            NSColor(self.state.color).setFill()
            circle.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
