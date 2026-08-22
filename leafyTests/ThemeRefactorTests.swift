import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    func testAppLanguagePreferenceSupportsSystemChineseAndEnglish() {
        XCTAssertEqual(AppLanguagePreference.storedValue(nil), .system)
        XCTAssertEqual(AppLanguagePreference.storedValue("zh-Hans"), .zhHans)
        XCTAssertEqual(AppLanguagePreference.storedValue("en-US"), .enUS)
        XCTAssertEqual(AppLanguagePreference.storedValue("unsupported"), .system)
        XCTAssertEqual(AppLanguagePreference.zhHans.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguagePreference.enUS.localeIdentifier, "en-US")
        XCTAssertEqual(AppLanguagePreference.zhHans.weekdayTitle(for: 1), "周一")
        XCTAssertEqual(AppLanguagePreference.zhHans.weekdayTitle(for: 7), "周日")
        XCTAssertEqual(AppLanguagePreference.zhHans.timetableWeekdayTitle(for: 1), "周一")
        XCTAssertEqual(AppLanguagePreference.zhHans.timetableWeekdayTitle(for: 7), "周日")
    }

    func testExplicitLocalizationReturnsRequestedLanguageAndFormatsValues() {
        XCTAssertEqual(L10n.text("语言", language: .zhHans), "语言")
        XCTAssertEqual(L10n.text("第 %d 周", language: .zhHans, 3), "第 3 周")
        XCTAssertEqual(L10n.text("语言", language: .enUS), "Language")
        XCTAssertEqual(AppLanguagePreference.enUS.weekdayTitle(for: 1), "Monday")
        XCTAssertEqual(
            (1...7).map { AppLanguagePreference.enUS.timetableWeekdayTitle(for: $0) },
            ["Mon.", "Tues.", "Wed.", "Thurs.", "Fri.", "Sat.", "Sun."]
        )
        XCTAssertEqual(AcademicPrimaryTab.learning.compactTitle(language: .enUS), "Spaces")
        XCTAssertEqual(AcademicPrimaryTab.classrooms.compactTitle(language: .enUS), "Study")
    }

    func testMissingLocalizationFallsBackToSourceKey() {
        let missingKey = "__leafy_missing_localization_test__"
        XCTAssertEqual(L10n.text(missingKey, language: .zhHans), missingKey)
        XCTAssertEqual(L10n.text(missingKey, language: .enUS), missingKey)
    }

    func testAppPreservesSystemDynamicTypeAndThemeFontsScaleRelatively() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("leafy/App/leafyApp.swift"),
            encoding: .utf8
        )
        let themeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("leafy/App/Theme/AppTheme.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appSource.contains(".environment(\\.dynamicTypeSize"))
        XCTAssertFalse(themeSource.contains("var dynamicTypeSize: DynamicTypeSize"))
        XCTAssertTrue(themeSource.contains("ScaledMetric(wrappedValue: baseSize, relativeTo: textStyle)"))
        XCTAssertTrue(themeSource.contains("scaledBaseSize * leafyFontScale"))
        XCTAssertTrue(themeSource.contains("relativeTo: .body"))
        XCTAssertTrue(themeSource.contains("relativeTo: .largeTitle"))
    }

    func testLanguagePreferenceSynchronizesToAppGroupDefaults() {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguagePreference.enUS.syncToAppGroup(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppLanguagePreference.appGroupStorageKey),
            AppLanguagePreference.enUS.rawValue
        )
    }

    func testExplicitLanguageDateFormattingUsesRequestedLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let chineseFormatter = DateFormatters.chineseDay(language: .zhHans)
        let englishFormatter = DateFormatters.chineseDay(language: .enUS)
        chineseFormatter.timeZone = calendar.timeZone
        englishFormatter.timeZone = calendar.timeZone

        XCTAssertEqual(chineseFormatter.string(from: date), "5月12日")
        XCTAssertEqual(englishFormatter.string(from: date), "May 12")

        let chineseMonthFormatter = DateFormatters.shortMonth(language: .zhHans)
        let englishMonthFormatter = DateFormatters.shortMonth(language: .enUS)
        chineseMonthFormatter.timeZone = calendar.timeZone
        englishMonthFormatter.timeZone = calendar.timeZone
        XCTAssertEqual(chineseMonthFormatter.string(from: date), "5月")
        XCTAssertEqual(englishMonthFormatter.string(from: date), "May")
    }

    func testTimetableBackgroundPaletteExtractsSoftColorsFromSolidImage() throws {
        let image = makePaletteTestImage(colors: [.systemRed])
        let palette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(palette.lightHexes.count, 7)
        XCTAssertEqual(palette.darkHexes.count, 7)
        XCTAssertNotEqual(palette.lightHexes, TimetableBackgroundPalette.fallbackLightHexes)
        XCTAssertTrue(palette.lightHexes.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
    }

    func testTimetableBackgroundPaletteUsesMultipleImageColors() throws {
        let image = makePaletteTestImage(colors: [.systemBlue, .systemOrange])
        let bluePalette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(makePaletteTestImage(colors: [.systemBlue]).cgImage))
        let mixedPalette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(mixedPalette.lightHexes.count, 7)
        XCTAssertNotEqual(mixedPalette.lightHexes, bluePalette.lightHexes)
    }

    func testTimetableBackgroundPaletteFallsBackForLowSaturationImage() throws {
        let image = makePaletteTestImage(colors: [UIColor(white: 0.5, alpha: 1)])
        let palette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(palette.lightHexes, TimetableBackgroundPalette.fallbackLightHexes)
        XCTAssertEqual(palette.darkHexes, TimetableBackgroundPalette.fallbackDarkHexes)
    }

    func testTimetableBackgroundPaletteFallsBackForOverDarkImage() throws {
        let image = makePaletteTestImage(colors: [UIColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 1)])
        let palette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(palette.lightHexes, TimetableBackgroundPalette.fallbackLightHexes)
        XCTAssertEqual(palette.darkHexes, TimetableBackgroundPalette.fallbackDarkHexes)
    }

    func testTimetableBackgroundConfigurationIgnoresPhotoWithoutCurrentKind() {
        withTemporaryUserDefaults { defaults in
            defaults.set(true, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set("legacy-background.jpg", forKey: TimetableBackgroundStore.filenameKey)
            defaults.set(0.42, forKey: TimetableBackgroundStore.imageOpacityKey)

            let configuration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(configuration.kind, .photo)
            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.filename, "legacy-background.jpg")
            XCTAssertEqual(configuration.imageOpacity, 0.42)
        }
    }

    func testTimetableBackgroundDefaultsToFitButKeepsExplicitFill() {
        withTemporaryUserDefaults { defaults in
            XCTAssertEqual(TimetableBackgroundConfiguration.load(defaults: defaults).displayMode, .fit)
            defaults.set(TimetableBackgroundDisplayMode.fill.rawValue, forKey: TimetableBackgroundStore.displayModeKey)
            XCTAssertEqual(TimetableBackgroundConfiguration.load(defaults: defaults).displayMode, .fill)
        }
    }

    func testTimetableBackgroundConfigurationKeepsPausedPhotoReference() {
        withTemporaryUserDefaults { defaults in
            defaults.set(false, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set("kept-background.jpg", forKey: TimetableBackgroundStore.filenameKey)
            defaults.set(TimetableBackgroundKind.photo.rawValue, forKey: TimetableBackgroundStore.kindKey)

            let configuration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(configuration.kind, .photo)
            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.filename, "kept-background.jpg")
            XCTAssertFalse(configuration.usesCustomBackground)
        }
    }

    func testTimetableBackgroundConfigurationIgnoresRemovedEffectKind() {
        withTemporaryUserDefaults { defaults in
            defaults.set(true, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set("effect", forKey: TimetableBackgroundStore.kindKey)
            defaults.set("kept-background.jpg", forKey: TimetableBackgroundStore.filenameKey)
            defaults.set("invalid-color", forKey: TimetableBackgroundStore.solidColorHexKey)

            let configuration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(configuration.kind, .photo)
            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.filename, "kept-background.jpg")
            XCTAssertEqual(configuration.solidColorHex, TimetableBackgroundStore.defaultSolidColorHex)
        }
    }

    func testTimetableBackgroundDraftEffectWithoutPhotoStaysDisabled() {
        withTemporaryUserDefaults { defaults in
            defaults.set(true, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set("effect", forKey: TimetableBackgroundStore.kindKey)

            let configuration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(configuration.kind, .photo)
            XCTAssertFalse(configuration.isEnabled)
            XCTAssertFalse(configuration.usesCustomBackground)
        }
    }

    func testTimetableBackgroundUnknownKindStaysDisabled() {
        withTemporaryUserDefaults { defaults in
            defaults.set(true, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set("unknown", forKey: TimetableBackgroundStore.kindKey)
            defaults.set("kept-background.jpg", forKey: TimetableBackgroundStore.filenameKey)

            let configuration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(configuration.kind, .photo)
            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.filename, "kept-background.jpg")
        }
    }

    func testTimetableBackgroundSolidColorNormalizesAndBuildsAdaptiveCoursePalettes() {
        withTemporaryUserDefaults { defaults in
            defaults.set(true, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set(TimetableBackgroundKind.solid.rawValue, forKey: TimetableBackgroundStore.kindKey)
            defaults.set("#2a7f62", forKey: TimetableBackgroundStore.solidColorHexKey)

            let configuration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(configuration.kind, .solid)
            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.solidColorHex, "#2A7F62")
            XCTAssertEqual(configuration.coursePalette(colorScheme: .light)?.count, 7)
            XCTAssertEqual(configuration.coursePalette(colorScheme: .dark)?.count, 7)
        }
    }

    func testTimetableBackgroundCatalogContainsPhotoAndSolidOnly() {
        XCTAssertEqual(TimetableBackgroundKind.allCases, [.photo, .solid])
    }

    func testTimetableBackgroundKindSwitchKeepsStoredPhotoReference() {
        withTemporaryUserDefaults { defaults in
            defaults.set(true, forKey: TimetableBackgroundStore.isEnabledKey)
            defaults.set("kept-background.jpg", forKey: TimetableBackgroundStore.filenameKey)
            defaults.set(TimetableBackgroundKind.solid.rawValue, forKey: TimetableBackgroundStore.kindKey)

            let solidConfiguration = TimetableBackgroundConfiguration.load(defaults: defaults)
            defaults.set(TimetableBackgroundKind.photo.rawValue, forKey: TimetableBackgroundStore.kindKey)
            let photoConfiguration = TimetableBackgroundConfiguration.load(defaults: defaults)

            XCTAssertEqual(solidConfiguration.filename, "kept-background.jpg")
            XCTAssertEqual(photoConfiguration.filename, "kept-background.jpg")
            XCTAssertTrue(photoConfiguration.isEnabled)
        }
    }

    func testTimetableBackgroundColorSerializationRoundTripsValidColors() throws {
        let color = try XCTUnwrap(TimetableBackgroundRGB(hex: "#123456"))
        let serialized = TimetableBackgroundStore.serialize(hexes: ["#123456", "#ABCDEF"])

        XCTAssertEqual(color.hexString, "#123456")
        XCTAssertEqual(serialized, "#123456,#ABCDEF")
        XCTAssertEqual(TimetableBackgroundStore.colors(from: serialized).count, 2)
    }

    func testCourseColorHashIndexStaysStable() {
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "Data StructuresAlice", colorCount: 7), 3)
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "森林生态王老师", colorCount: 7), 0)
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "", colorCount: 7), 0)
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "A", colorCount: 0), 0)
    }

    func testFloatingChromeDarkSelectionBackgroundDoesNotUseNearWhiteAccentSoft() {
        let color = UIColor(AppTheme.floatingChromeSelectedBackground(for: .green, colorScheme: .dark))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertFalse(red > 0.88 && green > 0.88 && blue > 0.88)
        XCTAssertLessThanOrEqual(alpha, 0.35)
    }

    func testIconPreferenceAcceptsOnlyCurrentConcretePresets() {
        XCTAssertEqual(
            LeafyAppIconAppearancePreference.allCases,
            [.green, .tiffanyBlue, .candyPink, .sunsetApricot, .irisPurple]
        )
        XCTAssertEqual(LeafyAppIconAppearancePreference.storedValue("tiffanyBlue"), .tiffanyBlue)
        XCTAssertEqual(LeafyAppIconAppearancePreference.storedValue("followTheme"), .green)
    }

    func testNewThemePresetsPreserveExactColorsAcrossSurfaces() {
        let sunsetSnapshot = LeafyWidgetThemeSnapshot(
            preferenceRaw: LeafyThemeColorPreferenceRaw.sunsetApricot.rawValue,
            customColorHex: LeafyThemeColorPreferenceRaw.defaultCustomColorHex
        )
        XCTAssertEqual(AppThemeColorPreference.storedValue("sunsetApricot"), .sunsetApricot)
        XCTAssertEqual(AppThemeColorPreference.sunsetApricot.title, "落日杏橙")
        XCTAssertEqual(
            LeafyWidgetThemePalette.baseColor(for: sunsetSnapshot),
            .init(255, 138, 61)
        )
        XCTAssertEqual(
            LeafyWidgetThemePalette.emphasisColor(for: sunsetSnapshot),
            .init(148, 80, 35)
        )
        XCTAssertEqual(
            LeafyWidgetThemePalette.softColor(for: sunsetSnapshot),
            .init(255, 236, 224)
        )
        let sunsetCommunityTheme = CommunityPostCardTheme(preferenceRawValue: "sunsetApricot")
        XCTAssertEqual(sunsetCommunityTheme.accentHex, "#FF8A3D")
        XCTAssertEqual(sunsetCommunityTheme.backgroundHex, "#FFECE0")

        let irisSnapshot = LeafyWidgetThemeSnapshot(
            preferenceRaw: LeafyThemeColorPreferenceRaw.irisPurple.rawValue,
            customColorHex: LeafyThemeColorPreferenceRaw.defaultCustomColorHex
        )
        XCTAssertEqual(AppThemeColorPreference.storedValue("irisPurple"), .irisPurple)
        XCTAssertEqual(AppThemeColorPreference.irisPurple.title, "鸢尾花紫")
        XCTAssertEqual(
            LeafyWidgetThemePalette.baseColor(for: irisSnapshot),
            .init(139, 108, 246)
        )
        XCTAssertEqual(
            LeafyWidgetThemePalette.emphasisColor(for: irisSnapshot),
            .init(81, 63, 143)
        )
        XCTAssertEqual(
            LeafyWidgetThemePalette.softColor(for: irisSnapshot),
            .init(236, 231, 254)
        )
        let irisCommunityTheme = CommunityPostCardTheme(preferenceRawValue: "irisPurple")
        XCTAssertEqual(irisCommunityTheme.accentHex, "#8B6CF6")
        XCTAssertEqual(irisCommunityTheme.backgroundHex, "#ECE7FE")
    }

    func testRootTabAllCasesOnlyContainPrimaryDestinations() {
        XCTAssertEqual(RootTab.allCases, [.timetable, .community, .schedule, .academics, .profile])
    }

    func testAcademicRootTabUsesCampusProductName() {
        XCTAssertEqual(RootTab.academics.title(language: .zhHans), "校园")
    }

    func testScheduleRootTabUsesDayTraceProductNameAndIcon() {
        XCTAssertEqual(RootTab.schedule.title(language: .zhHans), "日迹")
        XCTAssertEqual(RootTab.schedule.systemImage, "calendar.day.timeline.left")
    }

    func testAppStoreReviewCoordinatorRequiresThreeDifferentSyncDays() {
        let defaults = makeReviewUserDefaults()
        let notificationCenter = NotificationCenter()

        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, 10),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )
        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, 10),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )
        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, 11),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewDate(2026, 5, 12),
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testAppStoreReviewCoordinatorAllowsThirdDifferentSyncDay() {
        let defaults = makeReviewUserDefaults()
        seedThreeReviewSyncDays(defaults: defaults)

        XCTAssertTrue(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewDate(2026, 5, 13),
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testAppStoreReviewCoordinatorBlocksDemoInactiveAndSameVersion() {
        let defaults = makeReviewUserDefaults()
        seedThreeReviewSyncDays(defaults: defaults)
        let now = reviewDate(2026, 5, 13)

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: now,
            appVersion: "1.0",
            isDemoMode: true,
            isSceneActive: true,
            userDefaults: defaults
        ))
        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: now,
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: false,
            userDefaults: defaults
        ))

        AppStoreReviewCoordinator.markReviewRequestAttempted(
            now: now,
            appVersion: "1.0",
            userDefaults: defaults
        )

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewTestCalendar.date(byAdding: .day, value: 121, to: now)!,
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testAppStoreReviewCoordinatorCooldownAppliesAcrossVersions() {
        let defaults = makeReviewUserDefaults()
        seedThreeReviewSyncDays(defaults: defaults)
        let attemptedAt = reviewDate(2026, 5, 13)

        AppStoreReviewCoordinator.markReviewRequestAttempted(
            now: attemptedAt,
            appVersion: "1.0",
            userDefaults: defaults
        )

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewTestCalendar.date(byAdding: .day, value: 119, to: attemptedAt)!,
            appVersion: "2.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
        XCTAssertTrue(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewTestCalendar.date(byAdding: .day, value: 121, to: attemptedAt)!,
            appVersion: "2.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }
}
