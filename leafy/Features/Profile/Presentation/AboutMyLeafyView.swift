import SwiftUI

private enum MyLeafyStory: String, CaseIterable, Identifiable {
    case day, journal, campus, design, data
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "看清每一天"
        case .journal: "安排与记录，各得其所"
        case .campus: "校园事务，有条理"
        case .design: "细节，让使用更舒服"
        case .data: "数据边界，说清楚"
        }
    }
    var subtitle: String {
        switch self {
        case .day: "让时间、地点和接下来的安排一目了然。"
        case .journal: "放好计划，也留住生活中的小事。"
        case .campus: "把分散的信息，放在容易找到的地方。"
        case .design: "清晰的排版，克制的颜色，自然的交互。"
        case .data: "哪些留在设备，哪些由你主动分享。"
        }
    }
    var paragraphs: [String] {
        switch self {
        case .day: [
            "打开课表，就能确认今天上什么课、在哪里，以及接下来有什么安排。课程和个人日程共享时间视图，发生重叠时也能各自看清。",
            "一周适合看全局，三日视图适合看细节。Widget 则把近期安排放到主屏幕，让一次短暂的查看也有用。"
        ]
        case .journal: [
            "日程用来安排将来，随记用来留下当下。它们放在同一个日迹空间里，各自保持清楚的用途。",
            "从一条短记录开始，通过标签、搜索和回顾重新找到它。记录日迹展示累积的记录习惯，让平常的一天也有迹可循。"
        ]
        case .campus: [
            "成绩、考试、培养要求和空闲教室，属于不同的校园任务。按事情来组织入口，让需要的信息更容易找到。",
            "社区为同学交流留出空间。具体工具和社区能力取决于当前校园支持；教务结果仍以学校系统为准。"
        ]
        case .design: [
            "设计先服务于阅读。标题、辅助信息和操作有各自的层级，颜色帮助辨认，留白帮助集中注意。",
            "沿用 iPhone 熟悉的导航、列表和弹窗，让操作自然发生。主题、深浅色和显示密度，让同一套界面适合不同的使用习惯。",
            "把校园工具认真做好，意味着把这些细节放到每天的使用里，一次次检查和完善。"
        ]
        case .data: [
            "教务缓存、课程备注、随记和个人记录保存在当前设备。学校账号和密码用于学校登录，不作为社区内容上传。",
            "主动发布的帖子、评论、反馈和共享课表进入 MyLeafy 服务。共享课表只发布允许分享的课程字段，不包含成绩、备注和提醒。",
            "本地记录不提供自动云端备份。重要内容请使用已有导出能力妥善保存，具体操作与数据说明可以在帮助中心查看。"
        ]
        }
    }
}

struct AboutMyLeafyView: View {
    @Environment(\.leafyLanguage) private var language
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    Text(AppBrand.displayName).font(.largeTitle.bold())
                    Text(L10n.text("把校园工具认真做好", language: language))
                        .font(.title3.weight(.medium))
                    Text(L10n.text("从课表出发，照顾校园生活中的安排、记录与日常事务。", language: language))
                        .leafyBody().foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, AppSpacing.compact)

                ForEach(MyLeafyStory.allCases) { story in
                    NavigationLink {
                        MyLeafyStoryDetail(story: story)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            MyLeafyStoryIllustration(story: story)
                                .frame(height: 180)
                                .clipped()
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: AppSpacing.micro) {
                                    Text(L10n.text(story.title, language: language)).font(.title3.bold())
                                    Text(L10n.text(story.subtitle, language: language))
                                        .leafySubheadline().foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer(minLength: 8)
                                LeafyDisclosureIndicator().padding(.top, 5)
                            }
                            .padding(.horizontal, AppSpacing.page)
                            .padding(.bottom, AppSpacing.page)
                        }
                        .foregroundStyle(AppTheme.primaryText)
                        .leafyCardStyle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.text(story.title, language: language))
                    .accessibilityHint(L10n.text(story.subtitle, language: language))
                }
                Text("MyLeafy · \(version)")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.compact)
            }
            .padding(AppSpacing.page)
        }
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text("了解 MyLeafy", language: language))
        .leafyInlineNavigationTitle()
    }
}

private struct MyLeafyStoryDetail: View {
    @Environment(\.leafyLanguage) private var language
    let story: MyLeafyStory
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                MyLeafyStoryIllustration(story: story)
                    .frame(minHeight: 260).leafyCardStyle()
                    .accessibilityHidden(true)
                Text(L10n.text(story.title, language: language)).font(.largeTitle.bold())
                Text(L10n.text(story.subtitle, language: language))
                    .font(.title3).foregroundStyle(AppTheme.secondaryText)
                ForEach(story.paragraphs, id: \.self) { paragraph in
                    Text(L10n.text(paragraph, language: language))
                        .leafyBody().fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppSpacing.page).frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(LeafyPageBackground())
        .navigationTitle(L10n.text(story.title, language: language))
        .leafyInlineNavigationTitle()
    }
}

/// Fixed, read-only compositions. No model context or network dependency.
private struct MyLeafyStoryIllustration: View {
    @Environment(\.leafyLanguage) private var language
    let story: MyLeafyStory
    var body: some View {
        Group {
            switch story {
            case .day: timetable
            case .journal: journal
            case .campus: campus
            case .design: design
            case .data: data
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.accent.opacity(0.06))
        .accessibilityHidden(true)
    }
    private func text(_ key: String) -> String { L10n.text(key, language: language) }
    private func sample(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 10) {
            LeafyIconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(text(title)).font(.subheadline.weight(.semibold))
                Text(text(detail)).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }
    private var timetable: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<3) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(text(["周一", "周二", "周三"][day])).font(.caption.weight(.semibold))
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .fill(AppTheme.accent.opacity(day == 1 ? 0.32 : 0.18))
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(text(["设计基础", "高等数学", "大学英语"][day])).font(.caption.bold())
                                Text(["08:00", "09:50", "13:30"][day]).font(.caption2)
                            }.padding(9)
                        }
                        .frame(height: day == 1 ? 115 : 85)
                    if day == 0 {
                        Text(text("小组讨论")).font(.caption.weight(.medium))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }
    private var journal: some View {
        VStack(spacing: 10) {
            sample("小组讨论", icon: "calendar", detail: "今天 15:00 · 图书馆")
            sample("把今天的小事记下来", icon: "square.and.pencil", detail: "随记 · 日常")
        }
    }
    private var campus: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label(text("学校教学"), systemImage: "graduationcap")
                Label(text("自习安排"), systemImage: "book")
            }.font(.caption).foregroundStyle(AppTheme.accent)
            sample("空闲教室", icon: "door.left.hand.open", detail: "按日期和节次查询")
            sample("校园交流", icon: "bubble.left.and.bubble.right", detail: "同学的经验与消息")
        }
    }
    private var design: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aa  字").font(.system(size: 36, weight: .semibold))
            HStack(spacing: 12) {
                ForEach([0.18, 0.4, 0.7, 1.0], id: \.self) { opacity in
                    Circle().fill(AppTheme.accent.opacity(opacity)).frame(width: 30, height: 30)
                }
            }
            sample("外观", icon: "paintpalette", detail: "主题 · 显示密度 · 深浅色")
        }
    }
    private var data: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 36)).foregroundStyle(AppTheme.accent)
            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "iphone").font(.title2)
                    Text(text("当前设备")).font(.caption.weight(.semibold))
                    Text(text("随记与教务缓存")).font(.caption2).foregroundStyle(AppTheme.secondaryText)
                }
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.title2)
                    Text(text("主动分享")).font(.caption.weight(.semibold))
                    Text(text("社区与共享课表")).font(.caption2).foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }
}

#Preview { NavigationStack { AboutMyLeafyView() } }
