import SwiftUI

struct TodayView: View {
    @ObservedObject var viewModel: TodayViewModel
    let theme: StatusBarTimerTheme

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch viewModel.state {
            case .idle, .loading:
                loadingState
            case .empty:
                emptyState
            case .error(let message):
                errorState(message)
            case .loaded(let items):
                loadedState(items)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            await viewModel.loadToday()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Henter dagens opgaver…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.secondaryTextColor)
            Text("Ingen opgaver i dag")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryTextColor.opacity(0.9))
            Text("Træk ned for at opdatere.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.secondaryTextColor)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryTextColor.opacity(0.92))
                .multilineTextAlignment(.center)
            Button("Prøv igen") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.primaryTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.settingsPillBackground, in: Capsule())
            .statusBarHoverEffect()
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
    }

    private func loadedState(_ items: [TodayTaskItem]) -> some View {
        let sections = sectioned(items)
        return ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(sections, id: \.section) { bucket in
                    Text(bucket.section.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryTextColor.opacity(0.86))
                        .padding(.horizontal, 2)

                    ForEach(bucket.items) { item in
                        StatusBarTaskCard(
                            theme: theme,
                            title: item.title,
                            subtitle: subtitle(for: item),
                            onTap: {},
                            leading: {
                                Group {
                                    if let icon = resolvedIcon(for: item) {
                                        Text(icon)
                                            .font(.system(size: 12, weight: .semibold))
                                    } else {
                                        Image(systemName: item.kind == .play ? "play.fill" : "clock")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(theme.primaryTextColor.opacity(0.88))
                                    }
                                }
                                .frame(width: 27, height: 27)
                                .background(
                                    Circle()
                                        .fill(resolvedBackgroundColor(for: item))
                                )
                            },
                            trailing: {
                                EmptyView()
                            }
                        )
                    }
                }
            }
        }
    }

    private func subtitle(for item: TodayTaskItem) -> String {
        if item.kind == .play {
            return durationText(for: item.durationSeconds)
        }

        switch (item.startAt, item.endAt) {
        case let (start?, end?):
            return "\(Self.timeFormatter.string(from: start)) - \(Self.timeFormatter.string(from: end))"
        case let (start?, nil):
            return Self.timeFormatter.string(from: start)
        case let (nil, end?):
            return Self.timeFormatter.string(from: end)
        case (nil, nil):
            return durationText(for: item.durationSeconds)
        }
    }

    private func durationText(for durationSeconds: Int?) -> String {
        guard let durationSeconds, durationSeconds > 0 else {
            return "Varighed ukendt"
        }
        let minutes = max(1, Int(ceil(Double(durationSeconds) / 60.0)))
        return "\(minutes) min"
    }

    private func sectioned(_ items: [TodayTaskItem]) -> [(section: TodayTaskItem.Section, items: [TodayTaskItem])] {
        let grouped = Dictionary(grouping: items, by: \.section)
        return TodayTaskItem.Section.ordered.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section: section, items: items)
        }
    }

    private func resolvedIcon(for item: TodayTaskItem) -> String? {
        guard let icon = item.iconID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !icon.isEmpty
        else {
            return nil
        }
        return icon
    }

    private func resolvedBackgroundColor(for item: TodayTaskItem) -> Color {
        if let hex = item.backgroundColorHex,
           let resolved = Color(hex: hex)
        {
            return resolved
        }
        return theme.settingsPillBackground.opacity(0.84)
    }
}
