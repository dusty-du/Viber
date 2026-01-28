import SwiftUI

struct SettingsActions {
    let onToggleServer: () -> Void
    let onCopyURL: () -> Void
    let onCheckForUpdates: () -> Void
    let onQuit: () -> Void
}

enum SettingsSectionID: Hashable {
    case system
    case services
    case actions
    case about
}

enum SettingsAnimations {
    static let section = Animation.easeInOut(duration: 0.28)
    static let rowExpand = Animation.easeInOut(duration: 0.22)
    static let prompt = Animation.easeOut(duration: 0.18)
    static let toast = Animation.easeInOut(duration: 0.2)
}

struct SettingsSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(SettingsAnimations.section) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}

struct InlinePromptCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

struct AuthToastView: View {
    let message: String
    let success: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(success ? .green : .orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
