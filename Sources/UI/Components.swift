import SwiftUI

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.04, green: 0.47, blue: 0.40)
    static let accentLight = Color(red: 0.10, green: 0.66, blue: 0.55)
    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accentLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension DoctorStatus {
    var color: Color {
        switch self {
        case .available: return .green
        case .away: return .orange
        case .left: return .gray
        }
    }
}

// MARK: - Modifiers

struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StaggerIn: ViewModifier {
    let index: Int
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 26)
            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(min(index, 10)) * 0.06), value: shown)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(nanoseconds: 1_700_000_000)
                            withAnimation(.spring(response: 0.4)) { self.message = nil }
                        }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: message)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
    func staggerIn(_ index: Int, _ shown: Bool) -> some View { modifier(StaggerIn(index: index, shown: shown)) }
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Small views

struct StatusPill: View {
    let status: DoctorStatus
    var compact = false
    var body: some View {
        Label(status.title, systemImage: status.icon)
            .labelStyle(.titleAndIcon)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.14), in: Capsule())
    }
}

struct Chip: View {
    let title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background {
                    if selected {
                        Capsule().fill(Theme.gradient)
                    } else {
                        Capsule().fill(Color(.tertiarySystemFill))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct TagLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(Theme.accent)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Avatar: View {
    let doctor: Doctor?
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            if let data = doctor?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.gradient
                Text(doctor?.initials ?? "?")
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct CircleIconButton: View {
    let systemImage: String
    var tint: Color = Theme.accent
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(tint)
                .background(tint.opacity(0.13), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct ActionTile: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.accent
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.9, dampingFraction: 0.8), value: progress)
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.gradient)
                .symbolEffect(.pulse, options: .repeating)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.footnote)
                    .tint(Theme.accent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct DoctorRowLabel: View {
    let doctor: Doctor
    var showHospital = true
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Avatar(doctor: doctor, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(doctor.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if doctor.status != .available {
                StatusPill(status: doctor.status, compact: true)
            }
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if !doctor.specialty.isEmpty { parts.append(doctor.specialty) }
        if showHospital, let h = doctor.hospital { parts.append(h.name) }
        return parts.joined(separator: " · ")
    }
}

struct SectionTitle: View {
    let title: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Theme.accent)
            }
            Text(title).font(.headline)
            Spacer()
        }
    }
}
