import Combine
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

struct TeacherFilterToolbar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var search: String
    @Binding var selectedUnit: String?
    @Binding var selectedStars: Int?
    @Binding var isExpanded: Bool

    let availableUnits: [String]
    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            searchControl
                .animation(.snappy, value: isExpanded)

            ScrollView(.horizontal, showsIndicators: false) {
                filterMenus
                    .padding(.horizontal, 1)
            }
            .leafyTransparentHorizontalScrollRail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isExpanded {
            searchField
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选教师")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("搜索教师或学院", text: $search)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            Button {
                if search.isEmpty {
                    isExpanded = false
                } else {
                    search = ""
                }
            } label: {
                Image(systemName: search.isEmpty ? "chevron.up.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(search.isEmpty ? "收起筛选" : "清空搜索")
        }
        .padding(.horizontal, 12)
        .frame(width: 220 * leafyControlScale, height: 40 * leafyControlScale)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: AppTheme.cardElevated.opacity(0.96),
            isInteractive: true
        )
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("全部学院") {
                    selectedUnit = nil
                }
                ForEach(availableUnits, id: \.self) { unit in
                    Button {
                        selectedUnit = unit
                    } label: {
                        Label(unit, systemImage: selectedUnit == unit ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedUnit ?? "学院",
                    systemName: "building.columns",
                    isSelected: selectedUnit != nil
                )
            }

            Menu {
                Button("全部星级") {
                    selectedStars = nil
                }
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button {
                        selectedStars = stars
                    } label: {
                        Label("\(stars) 星", systemImage: selectedStars == stars ? "star.fill" : "star")
                    }
                }
            } label: {
                filterChip(
                    title: selectedStars.map { "\($0) 星" } ?? "星级",
                    systemName: "star",
                    isSelected: selectedStars != nil
                )
            }

            if hasActiveFilters {
                Button(action: clearFilters) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                        .frame(width: 36 * leafyControlScale, height: 36 * leafyControlScale)
                        .leafyGlassSurface(in: Circle(), isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func filterChip(title: String, systemName: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
            Text(title)
                .leafySubheadline()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.primaryText)
        .padding(.horizontal, 12 * leafyControlScale)
        .frame(height: 36 * leafyControlScale)
        .leafyCapsuleChipSurface(isSelected: isSelected)
    }
}

struct CourseFilterToolbar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var search: String
    @Binding var selectedCategory: String?
    @Binding var selectedStars: Int?
    @Binding var isExpanded: Bool

    let availableCategories: [String]
    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            searchControl
                .animation(.snappy, value: isExpanded)

            ScrollView(.horizontal, showsIndicators: false) {
                filterMenus
                    .padding(.horizontal, 1)
            }
            .leafyTransparentHorizontalScrollRail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isExpanded {
            searchField
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选课程")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("搜索课程或单位", text: $search)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            Button {
                if search.isEmpty {
                    isExpanded = false
                } else {
                    search = ""
                }
            } label: {
                Image(systemName: search.isEmpty ? "chevron.up.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(search.isEmpty ? "收起筛选" : "清空搜索")
        }
        .padding(.horizontal, 12)
        .frame(width: 220 * leafyControlScale, height: 40 * leafyControlScale)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: AppTheme.cardElevated.opacity(0.96),
            isInteractive: true
        )
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("全部分类") {
                    selectedCategory = nil
                }
                ForEach(availableCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category, systemImage: selectedCategory == category ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedCategory ?? "分类",
                    systemName: "tag",
                    isSelected: selectedCategory != nil
                )
            }

            Menu {
                Button("全部星级") {
                    selectedStars = nil
                }
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button {
                        selectedStars = stars
                    } label: {
                        Label("\(stars) 星", systemImage: selectedStars == stars ? "star.fill" : "star")
                    }
                }
            } label: {
                filterChip(
                    title: selectedStars.map { "\($0) 星" } ?? "星级",
                    systemName: "star",
                    isSelected: selectedStars != nil
                )
            }

            if hasActiveFilters {
                Button(action: clearFilters) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                        .frame(width: 36 * leafyControlScale, height: 36 * leafyControlScale)
                        .leafyGlassSurface(in: Circle(), isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func filterChip(title: String, systemName: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
            Text(title)
                .leafySubheadline()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.primaryText)
        .padding(.horizontal, 12 * leafyControlScale)
        .frame(height: 36 * leafyControlScale)
        .leafyCapsuleChipSurface(isSelected: isSelected)
    }
}

struct DishFilterToolbar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var search: String
    @Binding var selectedCanteen: String?
    @Binding var selectedLocation: String?
    @Binding var selectedStars: Int?
    @Binding var isExpanded: Bool

    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    private var availableLocations: [CampusDiningLocation] {
        if let selectedCanteen {
            return CampusDiningLocation.locations(for: selectedCanteen)
        }
        return CampusDiningLocation.all
    }

    var body: some View {
        HStack(spacing: 10) {
            searchControl
                .animation(.snappy, value: isExpanded)

            ScrollView(.horizontal, showsIndicators: false) {
                filterMenus
                    .padding(.horizontal, 1)
            }
            .leafyTransparentHorizontalScrollRail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isExpanded {
            searchField
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选菜品")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("搜索菜名或地点", text: $search)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            Button {
                if search.isEmpty {
                    isExpanded = false
                } else {
                    search = ""
                }
            } label: {
                Image(systemName: search.isEmpty ? "chevron.up.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(search.isEmpty ? "收起筛选" : "清空搜索")
        }
        .padding(.horizontal, 12)
        .frame(width: 220 * leafyControlScale, height: 40 * leafyControlScale)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: AppTheme.cardElevated.opacity(0.96),
            isInteractive: true
        )
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("全部食堂") {
                    selectedCanteen = nil
                    selectedLocation = nil
                }
                ForEach(CampusDiningLocation.canteens, id: \.self) { canteen in
                    Button {
                        selectedCanteen = canteen
                        if let currentLocation = selectedLocation,
                           !CampusDiningLocation.locations(for: canteen).contains(where: { $0.fullName == currentLocation }) {
                            selectedLocation = nil
                        }
                    } label: {
                        Label(canteen, systemImage: selectedCanteen == canteen ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedCanteen ?? "食堂",
                    systemName: "building.2",
                    isSelected: selectedCanteen != nil
                )
            }

            Menu {
                Button("全部地点") {
                    selectedLocation = nil
                }
                ForEach(availableLocations) { location in
                    Button {
                        selectedCanteen = location.canteen
                        selectedLocation = location.fullName
                    } label: {
                        Label(location.displayName, systemImage: selectedLocation == location.fullName ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedLocation.flatMap(CampusDiningLocation.displayName(for:)) ?? "地点",
                    systemName: "mappin.and.ellipse",
                    isSelected: selectedLocation != nil
                )
            }

            Menu {
                Button("全部星级") {
                    selectedStars = nil
                }
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button {
                        selectedStars = stars
                    } label: {
                        Label("\(stars) 星", systemImage: selectedStars == stars ? "star.fill" : "star")
                    }
                }
            } label: {
                filterChip(
                    title: selectedStars.map { "\($0) 星" } ?? "星级",
                    systemName: "star",
                    isSelected: selectedStars != nil
                )
            }

            if hasActiveFilters {
                Button(action: clearFilters) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                        .frame(width: 36 * leafyControlScale, height: 36 * leafyControlScale)
                        .leafyGlassSurface(in: Circle(), isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func filterChip(title: String, systemName: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
            Text(title)
                .leafySubheadline()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.primaryText)
        .padding(.horizontal, 12 * leafyControlScale)
        .frame(height: 36 * leafyControlScale)
        .leafyCapsuleChipSurface(isSelected: isSelected)
    }
}

struct CatalogSuggestionPromptButton: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .padding(.horizontal, 12 * leafyControlScale)
                .frame(height: 36 * leafyControlScale)
                .leafyCapsuleChipSurface(isSelected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct CatalogSuggestionSheetContext: Identifiable {
    let id = UUID()
    let type: CatalogSuggestionType
    let initialName: String
    let initialCategory: String?
    let initialLocation: String?
}

struct CatalogSuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @Environment(\.leafyLanguage) private var leafyLanguage

    let context: CatalogSuggestionSheetContext

    @State private var name: String
    @State private var unit = ""
    @State private var teacherName = ""
    @State private var category: String
    @State private var credit = ""
    @State private var selectedCanteen: String?
    @State private var selectedDishLocation: String?
    @State private var initialStars = 0
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUnit: String {
        if context.type == .dish {
            return selectedDishLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return unit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTeacherName: String {
        teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedCredit: Double? {
        let text = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var isCreditValid: Bool {
        guard context.type == .course else { return true }
        let text = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        guard let parsedCredit else { return false }
        return parsedCredit >= 0
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty &&
        !trimmedUnit.isEmpty &&
        (context.type == .teacher || !trimmedTeacherName.isEmpty) &&
        isCreditValid &&
        !isSubmitting
    }

    init(context: CatalogSuggestionSheetContext) {
        self.context = context
        _name = State(initialValue: context.initialName)
        _category = State(initialValue: context.initialCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "公选课")
        let initialLocation = context.initialLocation.flatMap(CampusDiningLocation.location(for:))
        _selectedCanteen = State(initialValue: initialLocation?.canteen)
        _selectedDishLocation = State(initialValue: initialLocation?.fullName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.type.sheetTitle)
                            .leafyTitle3()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(context.type.sheetSubtitle)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    if context.type == .dish {
                        Text("提交新菜名前，建议先在评菜页搜索菜名并切换地点确认是否已经有人提交过。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        CatalogSuggestionTextField(
                            title: context.type.nameFieldTitle,
                            placeholder: context.type.nameFieldPlaceholder,
                            text: $name
                        )

                        if context.type == .course {
                            CatalogSuggestionTextField(
                                title: "授课老师",
                                placeholder: "例如：张三",
                                text: $teacherName
                            )
                        }

                        if context.type == .dish {
                            CatalogSuggestionDiningLocationPicker(
                                selectedCanteen: $selectedCanteen,
                                selectedLocation: $selectedDishLocation
                            )
                        } else {
                            CatalogSuggestionOptionMenu(
                                title: context.type == .teacher ? "学院/单位" : "开课单位",
                                placeholder: context.type == .teacher ? "选择学院/单位" : "选择开课单位",
                                options: CommunityCatalogOptions.units,
                                selection: $unit
                            )
                        }

                        if context.type == .course {
                            CatalogSuggestionTextField(
                                title: "分类",
                                placeholder: "公选课",
                                text: $category
                            )

                            CatalogSuggestionTextField(
                                title: "学分",
                                placeholder: "可留空",
                                text: $credit,
                                keyboardType: .decimalPad
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("顺手评分（可选）")
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.primaryText)
                            TeacherStarPicker(selection: $initialStars)
                            if initialStars > 0 {
                                Button("清除评分") {
                                    initialStars = 0
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            }
                            Text("审核通过后，这个评分才会计入正式均分。")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("补充说明")
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.primaryText)
                            TextEditor(text: $note)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 92)
                                .padding(10)
                                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                                )
                        }

                        if !isCreditValid {
                            Text("学分需要填写为非负数字。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("提交建议")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(canSubmit ? AppTheme.accent : AppTheme.tertiaryText))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(context.type.navigationTitle)
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        if ReviewDemoMode.isEnabled {
            errorMessage = nil
            operationAlert = .success(
                L10n.text("已提交，等待审核。", language: leafyLanguage),
                buttonTitle: L10n.text("好的", language: leafyLanguage),
                action: { dismiss() }
            )
            return
        }

        let input = CatalogSuggestionInput(
            type: context.type,
            name: trimmedName,
            unit: trimmedUnit,
            teacherName: context.type == .course ? trimmedTeacherName : nil,
            category: context.type == .course ? category.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "公选课" : nil,
            credit: context.type == .course ? parsedCredit : nil,
            initialStars: initialStars == 0 ? nil : initialStars,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        do {
            try await dependencies.communityRepository.submitCatalogSuggestion(input: input)
            errorMessage = nil
            operationAlert = .success(
                L10n.text("已提交，等待审核。", language: leafyLanguage),
                buttonTitle: L10n.text("好的", language: leafyLanguage),
                action: { dismiss() }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CatalogSuggestionOptionMenu: View {
    let title: String
    let placeholder: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.isEmpty ? placeholder : selection)
                        .leafyBody()
                        .foregroundStyle(selection.isEmpty ? AppTheme.tertiaryText : AppTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct CatalogSuggestionDiningLocationPicker: View {
    @Binding var selectedCanteen: String?
    @Binding var selectedLocation: String?

    private var availableLocations: [CampusDiningLocation] {
        if let selectedCanteen {
            return CampusDiningLocation.locations(for: selectedCanteen)
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatalogSuggestionPickerMenu(
                title: "食堂",
                placeholder: "选择东区或西区食堂",
                options: CampusDiningLocation.canteens,
                selection: Binding(
                    get: { selectedCanteen ?? "" },
                    set: { canteen in
                        selectedCanteen = canteen.isEmpty ? nil : canteen
                        if let selectedLocation,
                           !CampusDiningLocation.locations(for: canteen).contains(where: { $0.fullName == selectedLocation }) {
                            self.selectedLocation = nil
                        }
                    }
                )
            )

            CatalogSuggestionPickerMenu(
                title: "地点",
                placeholder: selectedCanteen == nil ? "先选择食堂" : "选择楼层和餐厅",
                options: availableLocations.map(\.displayName),
                selection: Binding(
                    get: { selectedLocation.flatMap(CampusDiningLocation.displayName(for:)) ?? "" },
                    set: { displayName in
                        guard let location = availableLocations.first(where: { $0.displayName == displayName }) else {
                            selectedLocation = nil
                            return
                        }
                        selectedLocation = location.fullName
                    }
                )
            )
            .disabled(selectedCanteen == nil)
        }
    }
}

struct CatalogSuggestionPickerMenu: View {
    let title: String
    let placeholder: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.isEmpty ? placeholder : selection)
                        .leafyBody()
                        .foregroundStyle(selection.isEmpty ? AppTheme.tertiaryText : AppTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct CatalogSuggestionTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)
            TextField(placeholder, text: $text)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .leafyBody()
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

private extension CatalogSuggestionType {
    var sheetTitle: String {
        switch self {
        case .teacher:
            return "提交缺失老师"
        case .course:
            return "提交缺失课程"
        case .dish:
            return "提交缺失菜品"
        }
    }

    var sheetSubtitle: String {
        switch self {
        case .teacher:
            return "审核通过后会进入评教老师名录。"
        case .course:
            return "审核通过后会进入公选课课程库。"
        case .dish:
            return "审核通过后会进入评菜菜品库。"
        }
    }

    var navigationTitle: String {
        switch self {
        case .teacher:
            return "缺失老师"
        case .course:
            return "缺失课程"
        case .dish:
            return "缺失菜品"
        }
    }

    var nameFieldTitle: String {
        switch self {
        case .teacher:
            return "老师姓名"
        case .course:
            return "课程名"
        case .dish:
            return "菜名"
        }
    }

    var nameFieldPlaceholder: String {
        switch self {
        case .teacher:
            return "例如：张三"
        case .course:
            return "例如：森林生态学导论"
        case .dish:
            return "例如：番茄牛腩饭"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct TeacherSectionMessageCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title, language: leafyLanguage))
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
            Text(L10n.text(message, language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            if let actionTitle, let action {
                Button(L10n.text(actionTitle, language: leafyLanguage), action: action)
                    .foregroundStyle(AppTheme.accentEmphasis)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .leafyCardStyle()
    }
}

struct RatingLoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                }
                Text(isLoading ? "加载中" : "加载更多")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(AppTheme.primaryText)
            .leafyGlassSurface(in: Capsule(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct CommunityPostCard: View {
    let post: CommunityMockPost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(post.avatarColor.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(String(post.author.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(post.avatarColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(post.author)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(post.timestamp)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()
            }

            Text(post.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            Text(post.body)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            if !post.photoLabels.isEmpty {
                CommunityPhotoGrid(labels: post.photoLabels)
            }

            HStack(spacing: 16) {
                CommunityStat(icon: "heart", value: "\(post.likes)")
                CommunityStat(icon: "message", value: "\(post.comments)")
                CommunityStat(icon: "bookmark", value: post.tag)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct CommunityPhotoGrid: View {
    let labels: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(labels, id: \.self) { label in
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.subtleGreenGradient)
                    .frame(height: 88)
                    .overlay(
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accentEmphasis)
                    )
            }
        }
    }
}

struct CommunityStat: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(value)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.secondaryText)
    }
}

extension TeacherProfile {
    var ratingStarBucket: Int? {
        guard ratingCount > 0 else { return nil }
        return min(max(Int(ratingAverage.rounded()), 1), 5)
    }
}

extension CourseProfile {
    var ratingStarBucket: Int? {
        guard ratingCount > 0 else { return nil }
        return min(max(Int(ratingAverage.rounded()), 1), 5)
    }

    var creditText: String {
        if credit == floor(credit) {
            return "\(Int(credit)) 学分"
        }
        return String(format: "%.1f 学分", credit)
    }
}

extension DishProfile {
    var ratingStarBucket: Int? {
        guard ratingCount > 0 else { return nil }
        return min(max(Int(ratingAverage.rounded()), 1), 5)
    }

    var displayLocation: String {
        CampusDiningLocation.displayName(for: location) ?? location
    }
}

struct TeacherCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let summary: TeacherRatingSummary

    private var teacher: TeacherProfile {
        summary.teacher
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.accentSoft(for: themeColorPreference))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(teacher.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(teacher.name)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(teacher.unit)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(teacher.ratingCount == 0 ? "暂无" : String(format: "%.1f", teacher.ratingAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text("\(teacher.ratingCount) 人评分")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct CourseCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let summary: CourseRatingSummary

    private var course: CourseProfile {
        summary.course
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.accentSoft(for: themeColorPreference))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(course.name)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                Text("\(course.displayUnit) · \(course.displayCategory) · \(course.creditText)")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(course.ratingCount == 0 ? "暂无" : String(format: "%.1f", course.ratingAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text("\(course.ratingCount) 人评分")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct DishCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let summary: DishRatingSummary

    private var dish: DishProfile {
        summary.dish
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.accentSoft(for: themeColorPreference))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(dish.name)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                Text(dish.displayLocation)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(dish.ratingCount == 0 ? "暂无" : String(format: "%.1f", dish.ratingAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text("\(dish.ratingCount) 人评分")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct ComposerPlaceholderSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                LeafySectionTitle("发布帖子", subtitle: "当前阶段先验证半屏模态和表单结构，发布行为继续使用 Mock。")

                VStack(alignment: .leading, spacing: 12) {
                    Text("标题")
                        .font(.headline)
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .frame(height: 52)

                    Text("正文")
                        .font(.headline)
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .frame(height: 160)
                }
                .padding(18)
                .leafyCardStyle()

                Spacer()
            }
            .padding(AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle("发布")
            .leafyInlineNavigationTitle()
        }
    }
}

struct CommunityPostDetailSheet: View {
    let post: CommunityMockPost

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    CommunityPostCard(post: post)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评论区")
                            .font(.headline)
                        ForEach(post.mockComments, id: \.self) { comment in
                            Text(comment)
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .leafyCardStyle()
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("帖子详情")
            .leafyInlineNavigationTitle()
        }
    }
}
