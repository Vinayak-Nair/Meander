import SwiftUI
import MeanderKit

/// Floating "Added to dictionary" notification shown when Meander auto-learns a
/// correction. Lets the user undo the addition (Remove) or dismiss the toast
/// (x) without opening the dashboard.
struct LearnedToastView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.accentSolid)
                Text("Added to dictionary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.text(0.55))
                Spacer(minLength: 16)
                Button { state.dismissLearnedToast() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ink.text(0.5))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            ForEach(state.learnedToastTerms, id: \.self) { term in
                HStack(spacing: 10) {
                    Text(term)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Button { state.removeLearnedTerm(term) } label: {
                        Text("Remove")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.text(0.85))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        .padding(20) // breathing room for the shadow inside the borderless panel
    }
}
