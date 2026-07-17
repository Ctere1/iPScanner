import SwiftUI

// MARK: - Resizable divider

struct ResizableDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    @State private var startWidth: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Divider()
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .contentShape(.rect)
        }
        .frame(width: 6)
        .onHover { hovering in
            // Push/pop is balanced; onDisappear handles the case where the
            // inspector is removed while the cursor is still inside the area.
            if hovering, !isHovering {
                NSCursor.resizeLeftRight.push()
                isHovering = true
            } else if !hovering, isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if startWidth == nil { startWidth = width }
                    let proposed = (startWidth ?? width) - Double(value.translation.width)
                    width = min(max(proposed, minWidth), maxWidth)
                }
                .onEnded { _ in startWidth = nil }
        )
    }
}
