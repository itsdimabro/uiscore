import SwiftUI
import ScreenCheckCore

/// Undo toast: a grey container whose fill grows linearly over the undo window; the whole container undoes.
struct UndoToast: View {
    @ObservedObject var m: AppModel
    let name: String
    @State private var filled = false
    var progress: CGFloat? = nil
    var body: some View {
        let p = progress ?? (filled ? 1 : 0)
        Button { m.undoDelete() } label: {
            ZStack(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(T.toastFill).frame(width: g.size.width * p)
                }
                HStack {
                    Text("Deleted \(name)").font(.system(size: 12)).foregroundStyle(T.ink2).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Undo").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink)
                }.padding(.horizontal, 12)
            }
            .frame(height: 36)
            .background(T.soft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).focusable(false).accessibilityLabel("Undo delete")
        .onAppear { if progress == nil { withAnimation(.linear(duration: PendingDeletions.window)) { filled = true } } }
    }
}
