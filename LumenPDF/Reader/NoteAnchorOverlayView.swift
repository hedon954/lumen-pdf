import SwiftUI

struct NoteAnchorOverlayView: View {
    let anchors: [NoteAnchorPosition]
    let onOpen: (NoteAnchorPosition) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(anchors) { anchor in
                Button {
                    onOpen(anchor)
                } label: {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.accentColor.opacity(0.88), in: Circle())
                        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .help("打开笔记")
                .accessibilityLabel("打开笔记")
                .position(anchor.point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!anchors.isEmpty)
    }
}
