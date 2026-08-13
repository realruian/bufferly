import AppKit
import SwiftUI

/// Paste 式 Power Search：自由文本与筛选标签共处一个搜索框，筛选入口也收进框内。
struct PowerSearchView: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    var searchFocused: FocusState<Bool>.Binding
    @Binding var suggestionsVisible: Bool
    @Binding var selectedSuggestionIndex: Int
    @Binding var filterPalettePresented: Bool
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var suggestions: [ClipFilterToken] {
        viewModel.filterSuggestions
    }

    private var showsSuggestions: Bool {
        suggestionsVisible && !suggestions.isEmpty && !filterPalettePresented
    }

    var body: some View {
        HStack(spacing: 6) {
            HugeIconView(name: "search-01", fallbackSystemName: "magnifyingglass")
                .frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            ForEach(viewModel.activeFilterTokens) { token in
                FilterTokenChip(viewModel: viewModel, token: token)
            }

            TextField("搜索剪贴板", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused(searchFocused)
                .frame(minWidth: 54, maxWidth: .infinity)
                .layoutPriority(1)
                .onSubmit(onSubmit)
                .onTapGesture {
                    suggestionsVisible = !viewModel.filterSuggestions.isEmpty
                }
                .accessibilityLabel("搜索剪贴板")

            if !viewModel.query.isEmpty || viewModel.filter.isActive {
                Button {
                    viewModel.clearSearchAndFilters()
                    suggestionsVisible = false
                    selectedSuggestionIndex = 0
                } label: {
                    HugeIconView(name: "cancel-circle", fallbackSystemName: "xmark.circle.fill")
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索和筛选")
                .help("清除搜索和筛选")
            }

            Button {
                suggestionsVisible = false
                filterPalettePresented = true
            } label: {
                HugeIconView(name: "filter-horizontal", fallbackSystemName: "line.3.horizontal.decrease")
                    .frame(width: 15, height: 15)
                    .foregroundStyle(viewModel.filter.isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.filter.isActive ? "编辑筛选，已启用 \(viewModel.activeFilterCount) 项" : "筛选")
            .help("筛选（⌘F）")
            .popover(
                isPresented: $filterPalettePresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                PowerSearchFilterPalette(viewModel: viewModel)
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(width: 320, height: 32)
        .background {
            if reduceTransparency {
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        }
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Capsule())
        .overlay(alignment: .topLeading) {
            if showsSuggestions {
                FilterSuggestionList(
                    viewModel: viewModel,
                    suggestions: suggestions,
                    selectedIndex: selectedSuggestionIndex,
                    onSelect: applySuggestion
                )
                .padding(.leading, 20)
                .offset(y: 38)
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .zIndex(20)
    }

    private func applySuggestion(_ token: ClipFilterToken) {
        viewModel.applyFilterToken(token)
        viewModel.query = ""
        suggestionsVisible = false
        selectedSuggestionIndex = 0
        searchFocused.wrappedValue = true
    }
}

private struct FilterTokenChip: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    let token: ClipFilterToken

    var body: some View {
        Button {
            viewModel.removeFilterToken(token)
        } label: {
            HStack(spacing: 4) {
                FilterTokenIcon(viewModel: viewModel, token: token, size: 12)
                Text(token.title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.secondary.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移除\(tokenCategoryName(token))筛选：\(token.title)")
        .help("移除筛选：\(token.title)")
    }
}

private struct FilterSuggestionList: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    let suggestions: [ClipFilterToken]
    let selectedIndex: Int
    let onSelect: (ClipFilterToken) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, token in
                Button {
                    onSelect(token)
                } label: {
                    HStack(spacing: 8) {
                        FilterTokenIcon(viewModel: viewModel, token: token, size: 15)
                        Text(token.title)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(tokenCategoryName(token))
                            .font(.caption)
                            .foregroundStyle(
                                index == selectedIndex
                                    ? Color.white.opacity(0.8)
                                    : Color.secondary.opacity(0.7)
                            )
                    }
                    .foregroundStyle(index == selectedIndex ? Color.white : Color.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        index == selectedIndex ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tokenCategoryName(token))筛选：\(token.title)")
                .accessibilityValue(index == selectedIndex ? "已选择" : "未选择")
                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
            }
        }
        .padding(5)
        .frame(width: 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("筛选建议")
    }
}

private struct PowerSearchFilterPalette: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    @State private var showsAllSources = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        Group {
            if showsAllSources {
                allSources
            } else {
                overview
            }
        }
        .padding(12)
        .frame(width: 370)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterSection("类型", tokens: viewModel.availableTypeNames.map(ClipFilterToken.type))

            filterSection(
                "来源",
                tokens: Array(viewModel.recentSources.prefix(8)).map(ClipFilterToken.source),
                showsMore: viewModel.recentSources.count > 8
            )

            filterSection(
                "时间",
                tokens: ClipTimeFilter.allCases.filter { $0 != .all }.map(ClipFilterToken.time)
            )
        }
    }

    private var allSources: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showsAllSources = false
            } label: {
                HStack(spacing: 6) {
                    HugeIconView(name: "arrow-left-01", fallbackSystemName: "chevron.left")
                        .frame(width: 14, height: 14)
                    Text("全部来源")
                }
                .font(.headline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回常用筛选")

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(viewModel.availableSources, id: \.self) { source in
                        paletteChip(.source(source))
                    }
                }
            }
            .frame(maxHeight: 250)
        }
    }

    @ViewBuilder
    private func filterSection(_ title: String, tokens: [ClipFilterToken], showsMore: Bool = false) -> some View {
        if !tokens.isEmpty || showsMore {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(tokens) { token in
                        paletteChip(token)
                    }

                    if showsMore {
                        Button {
                            showsAllSources = true
                        } label: {
                            HStack(spacing: 6) {
                                HugeIconView(name: "more-horizontal", fallbackSystemName: "ellipsis")
                                    .frame(width: 13, height: 13)
                                Text("更多")
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("显示全部来源")
                    }
                }
            }
        }
    }

    private func paletteChip(_ token: ClipFilterToken) -> some View {
        let isSelected = viewModel.activeFilterTokens.contains(token)
        return Button {
            viewModel.toggleFilterToken(token)
        } label: {
            HStack(spacing: 6) {
                FilterTokenIcon(viewModel: viewModel, token: token, size: 13)
                Text(token.title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tokenCategoryName(token))：\(token.title)")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FilterTokenIcon: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    let token: ClipFilterToken
    let size: CGFloat

    var body: some View {
        Group {
            switch token {
            case .type(let typeName):
                let kind = ClipKind.allCases.first { $0.displayName == typeName }
                HugeIconView(
                    name: kind?.hugeIconName ?? "text-align-left",
                    fallbackSystemName: kind?.symbolName ?? "text.alignleft"
                )
            case .source(let source):
                if
                    let bundleID = viewModel.sourceBundleID(for: source),
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    HugeIconView(name: "ai-content-generator-01", fallbackSystemName: "app")
                }
            case .time:
                HugeIconView(name: "calendar-03", fallbackSystemName: "calendar")
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private func tokenCategoryName(_ token: ClipFilterToken) -> String {
    switch token {
    case .type:
        "类型"
    case .source:
        "来源"
    case .time:
        "时间"
    }
}
