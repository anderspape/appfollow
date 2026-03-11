import SwiftUI

struct StatusBarTaskLibraryDrawer: View {
    enum TaskLibraryTab: String, CaseIterable, Identifiable {
        case explore = "Explore"
        case mine = "My favorites"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mine:
                return "􀊵 Favorites"
            case .explore:
                return "􀊫 Explore"
            }
        }
    }

    let userTemplates: [TaskTemplate]
    let premadeTemplates: [TaskTemplate]
    let savedPremadeTemplateIDs: Set<String>
    let theme: StatusBarTimerTheme
    let isEmbedded: Bool
    let onClose: () -> Void
    let onLoadTemplate: (TaskTemplate) -> Void
    let onStartTemplate: (TaskTemplate) -> Void
    let onTogglePremadeFavorite: (TaskTemplate) -> Void
    let onDeleteTemplate: (TaskTemplate) -> Void

    @Binding var selectedTab: TaskLibraryTab
    @Binding var selectedCategoryName: String?
    @Binding var currentPage: Int
    private let pageSize = 10
    private let popularCategoryName = "🔥 Popular"
    private let prioritizedCategoryNames: [String] = ["Work", "Study"]
    private let popularPremadeTemplateIDs: [String] = [
        "premade-work-deep-work",
        "premade-work-2",
        "premade-admin-inbox-zero",
        "premade-admin-4",
        "premade-admin-8",
        "premade-breaks-reset-block",
        "premade-breaks-7",
        "premade-human-needs-3",
        "premade-household-2",
        "premade-self-care-3"
    ]

    var body: some View {
        if isEmbedded {
            content
        } else {
            content
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                        .fill(theme.settingsCardBackground.opacity(theme.colorScheme == .dark ? 0.96 : 0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(theme.colorScheme == .dark ? 0.18 : 0.3), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(theme.colorScheme == .dark ? 0.28 : 0.14), radius: 16, y: 6)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text("Library")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.secondaryTextColor)

                HStack {
                    Spacer(minLength: 0)
                    StatusBarToolbarButton(
                        systemName: isEmbedded ? "arrow.right" : "xmark",
                        tint: theme.primaryTextColor,
                        action: onClose
                    )
                }
            }

            tabSelector
            if selectedTab == .explore {
                categorySelector
            }

            if paginatedTemplates.isEmpty {
                Text(emptyStateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryTextColor)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedTemplates) { template in
                            let isMineTab = selectedTab == .mine
                            let canToggleFavorite = isMineTab || template.source == .premade
                            let isFavorite = isMineTab || isSavedPremade(template)
                            StatusBarTaskLibraryCard(
                                template: template,
                                theme: theme,
                                showsFavoriteButton: canToggleFavorite,
                                isFavorite: isFavorite,
                                onLoad: { onLoadTemplate(template) },
                                onStart: { onStartTemplate(template) },
                                onToggleFavorite: {
                                    if isMineTab {
                                        onDeleteTemplate(template)
                                    } else {
                                        onTogglePremadeFavorite(template)
                                    }
                                },
                                onDelete: { onDeleteTemplate(template) }
                            )
                        }
                    }
                }
            }

            if totalPages > 1 {
                paginationControls
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: selectedTab) { _ in
            currentPage = 0
            if selectedTab == .mine {
                selectedCategoryName = nil
            } else if let selectedCategoryName {
                if selectedCategoryName != popularCategoryName && !availableCategoryNames.contains(selectedCategoryName) {
                    self.selectedCategoryName = popularCategoryName
                }
            } else {
                selectedCategoryName = popularCategoryName
            }
        }
        .onChange(of: selectedCategoryName) { _ in
            currentPage = 0
        }
        .onChange(of: filteredTemplates.map(\.id)) { _ in
            clampCurrentPage()
        }
        .onAppear {
            if selectedTab == .explore, selectedCategoryName == nil {
                selectedCategoryName = popularCategoryName
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(TaskLibraryTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? theme.primaryTextColor : theme.secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? theme.settingsPillBackground.opacity(1.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect()
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(theme.settingsPillBackground.opacity(0))
        )
        .overlay(
            Capsule()
                .stroke(theme.taskCardStrokeColor.opacity(0.9), lineWidth: 0.75)
        )
    }

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(title: popularCategoryName, isSelected: selectedCategoryName == popularCategoryName) {
                    selectedCategoryName = popularCategoryName
                }

                ForEach(availableCategoryNames, id: \.self) { categoryName in
                    categoryPill(title: categoryName, isSelected: selectedCategoryName == categoryName) {
                        selectedCategoryName = categoryName
                    }
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 22)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, -22)
    }

    private func categoryPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let isPopular = title == popularCategoryName
        let category = SessionCategory.named(title)
        let popularActiveFill = Color(red: 1.0, green: 0.84, blue: 0.62)
        let selectedFill: Color? = {
            if isPopular {
                return popularActiveFill
            }
            return category.flatMap { Color(hex: $0.colorHex) }
        }()
        let categoryEmoji = category?.emoji
        let textColor: Color = {
            guard isSelected else { return theme.secondaryTextColor }
            if isPopular {
                return .black.opacity(0.82)
            }
            return selectedCategoryTextColor(for: category)
        }()
        let selectedOpacity: Double = {
            guard isSelected else { return 1.0 }
            if isPopular {
                return theme.colorScheme == .dark ? 0.9 : 0.96
            }
            return theme.colorScheme == .dark ? 0.46 : 0.86
        }()
        let fillColor = isSelected
            ? (selectedFill?.opacity(selectedOpacity) ?? theme.settingsPillBackground)
            : theme.settingsPillBackground.opacity(0)
        let strokeColor = isSelected
            ? (selectedFill?.opacity(1) ?? theme.taskCardStrokeColor.opacity(0))
            : theme.taskCardStrokeColor.opacity(0)
        let strokeWidth: CGFloat = isSelected ? 0.9 : 0.6

        return Button(action: action) {
            HStack(spacing: categoryEmoji == nil ? 0 : 4) {
                if let categoryEmoji {
                    Text(categoryEmoji)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                Capsule()
                    .fill(fillColor)
            )
            .overlay(
                Capsule()
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
        }
        .buttonStyle(.plain)
        .statusBarHoverEffect()
    }

    private var templatesForSelectedTab: [TaskTemplate] {
        switch selectedTab {
        case .mine:
            return sortedUserTemplates
        case .explore:
            return premadeTemplates
        }
    }

    private var filteredTemplates: [TaskTemplate] {
        guard selectedTab == .explore else {
            return templatesForSelectedTab
        }

        let activeCategory = selectedCategoryName ?? popularCategoryName
        if activeCategory == popularCategoryName {
            return popularTemplates
        }

        return templatesForSelectedTab.filter { $0.resolvedCategoryName == activeCategory }
    }

    private var popularTemplates: [TaskTemplate] {
        let templatesByPremadeID = Dictionary(
            uniqueKeysWithValues: premadeTemplates.map { template in
                (template.premadeTemplateID ?? template.id.uuidString, template)
            }
        )

        var curated = popularPremadeTemplateIDs.compactMap { templatesByPremadeID[$0] }
        if curated.count < pageSize {
            let curatedIDs = Set(curated.map { $0.premadeTemplateID ?? $0.id.uuidString })
            let fallback = premadeTemplates.filter { template in
                let id = template.premadeTemplateID ?? template.id.uuidString
                return !curatedIDs.contains(id)
            }
            curated.append(contentsOf: fallback.prefix(pageSize - curated.count))
        }

        return Array(curated.prefix(pageSize))
    }

    private var paginatedTemplates: [TaskTemplate] {
        guard !filteredTemplates.isEmpty else { return [] }
        let safePage = min(max(0, currentPage), max(0, totalPages - 1))
        let start = safePage * pageSize
        let end = min(start + pageSize, filteredTemplates.count)
        guard start < end else { return [] }
        return Array(filteredTemplates[start..<end])
    }

    private var totalPages: Int {
        let count = filteredTemplates.count
        guard count > 0 else { return 1 }
        return Int(ceil(Double(count) / Double(pageSize)))
    }

    private var paginationControls: some View {
        HStack(spacing: 10) {
            Button {
                currentPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryTextColor)
                    .frame(width: 24, height: 24)
                    .background(theme.settingsPillBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect(enabled: currentPage > 0)
            .disabled(currentPage == 0)

            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)

            Button {
                currentPage = min(totalPages - 1, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryTextColor)
                    .frame(width: 24, height: 24)
                    .background(theme.settingsPillBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect(enabled: currentPage < totalPages - 1)
            .disabled(currentPage >= totalPages - 1)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var sortedUserTemplates: [TaskTemplate] {
        userTemplates.sorted { lhs, rhs in
            (lhs.updatedAt) > (rhs.updatedAt)
        }
    }

    private var availableCategoryNames: [String] {
        let categoriesInSelection = Set(templatesForSelectedTab.compactMap(\.resolvedCategoryName))
        let ordered = SessionCategory.all.map(\.name).filter { categoriesInSelection.contains($0) }
        let prioritized = prioritizedCategoryNames.filter { ordered.contains($0) }
        let prioritizedSet = Set(prioritized)
        let remainder = ordered.filter { !prioritizedSet.contains($0) }
        return prioritized + remainder
    }

    private var emptyStateText: String {
        switch selectedTab {
        case .mine:
            return "No favorites yet"
        case .explore:
            return "No premade tasks found"
        }
    }

    private func isSavedPremade(_ template: TaskTemplate) -> Bool {
        guard template.source == .premade else { return false }
        guard let premadeTemplateID = template.premadeTemplateID else { return false }
        return savedPremadeTemplateIDs.contains(premadeTemplateID)
    }

    private func clampCurrentPage() {
        currentPage = min(max(0, currentPage), max(0, totalPages - 1))
    }

    private func selectedCategoryTextColor(for category: SessionCategory?) -> Color {
        guard let category,
              let normalized = HexColor.normalize(category.colorHex),
              let rgb = Int(String(normalized.dropFirst()), radix: 16)
        else {
            return theme.primaryTextColor
        }
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance < 0.58 ? .white : .black.opacity(0.85)
    }
}

private struct StatusBarTaskLibraryCard: View {
    let template: TaskTemplate
    let theme: StatusBarTimerTheme
    let showsFavoriteButton: Bool
    let isFavorite: Bool
    let onLoad: () -> Void
    let onStart: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    @State private var isFavoriteButtonHovered = false
    @State private var isStartButtonHovered = false

    var body: some View {
        StatusBarTaskCard(
            theme: theme,
            title: template.title,
            subtitle: metaText,
            onTap: onLoad,
            leading: {
                Text(template.emoji)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .background(
                        Circle()
                            .fill(Color(hex: template.accentHex) ?? Color(red: 0.93, green: 0.92, blue: 0.99))
                    )
            },
            trailing: {
                HStack(spacing: 6) {
                    if showsFavoriteButton {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isFavorite ? theme.favoriteAccentColor : theme.primaryTextColor)
                                .frame(width: 24, height: 24)
                                .background(theme.settingsPillBackground.opacity(isFavoriteButtonHovered ? 1 : 0), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .statusBarHoverEffect()
                        .onHover { hovering in
                            isFavoriteButtonHovered = hovering
                        }
                    }

                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.primaryTextColor.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .background(theme.settingsPillBackground.opacity(isStartButtonHovered ? 1 : 0), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .statusBarHoverEffect()
                    .onHover { hovering in
                        isStartButtonHovered = hovering
                    }
                }
            }
        )
    }

    private var metaText: String {
        return StatusBarTimerDraftHelpers.formattedDuration(template.effectiveFocusMinutes)
    }

}
