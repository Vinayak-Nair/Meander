import SwiftUI

/// Floating, click-through HUD shown while dictation is active. A compact glass
/// pill that hugs its content: a flowing glowing wave while listening, growing
/// to show the live partial transcript for streaming engines, then a
/// transcribing state.
struct LiveOverlayView: View {
    @EnvironmentObject var state: AppState

    private var hasText: Bool { !state.livePartialText.isEmpty }

    var body: some View {
        Group {
            switch state.status {
            case .recording:
                listening
            case .transcribing:
                transcribing
            default:
                EmptyView()
            }
        }
        // Fill the transparent panel and float the pill in its centre so it stays
        // anchored on screen no matter how the content resizes.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.16), value: state.livePartialText)
        .animation(.smooth(duration: 0.24), value: state.status)
    }

    private var listening: some View {
        Group {
            if hasText {
                card(expanded: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            waveform
                            Text("Listening…")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Ink.text(0.55))
                        }
                        Text(state.livePartialText)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 440, alignment: .leading)
                    }
                }
            } else {
                // Compact, Wispr-sized: just the small glowing wave, no label.
                card(expanded: false) { waveform }
            }
        }
    }

    private var waveform: some View {
        LiveWaveform(active: true, level: state.audioLevel, spectrum: state.audioSpectrum)
            .frame(width: 64, height: 18)
    }

    private var transcribing: some View {
        card(expanded: false) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Transcribing…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Ink.text(0.55))
            }
        }
    }

    /// A content-hugging dark glass pill with a top-lit hairline border and one
    /// quiet shadow, so the glowing wave reads against it.
    private func card<Content: View>(expanded: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        let corner: CGFloat = 22
        return content()
            .padding(.horizontal, expanded ? 20 : 14)
            .padding(.vertical, expanded ? 15 : 9)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Ink.bgTop.opacity(0.7))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
            .preferredColorScheme(.dark)
    }
}
