import SafariServices
import SwiftUI

struct TeachingCultivationSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("学校教学", subtitle: sectionSubtitle)

            ToolEntryCard(title: "成绩查询", subtitle: isCustomCampus ? "按模板导入成绩表，查看本地成绩记录" : "查看课程成绩、绩点等", icon: "chart.bar.doc.horizontal") {
                openRoute(.grades)
            }

            ToolEntryCard(title: "考试安排", subtitle: isCustomCampus ? "手动添加或导入考试时间和地点" : "查看考试时间和地点", icon: "calendar.badge.clock") {
                openRoute(.examSchedule)
            }

            if !isCustomCampus {
                ToolEntryCard(title: "教学与培养", subtitle: "查看课程、学分、培养目标与课程体系", icon: "graduationcap.fill") {
                    openRoute(.teachingPlan)
                }

                ToolEntryCard(title: "校历与作息", subtitle: "查看学期校历和作息时间", icon: "calendar.badge.clock") {
                    openRoute(.schoolCalendar)
                }

                ToolEntryCard(title: "综素测算", subtitle: "估算综素分，整理材料", icon: "function") {
                    openRoute(.comprehensiveQuality)
                }
            }
        }
    }

    private var sectionSubtitle: String {
        if isCustomCampus {
            return "通用学校以本地维护为主：成绩和考试可按模板导入，培养信息可手动维护。"
        }
        return "集中显示成绩、考试、校历和培养信息；个人教务数据仅保存在本机。"
    }
}

struct ClassroomsSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    @State private var browserItem: LibrarySeatReservationBrowserItem?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("自习安排", subtitle: "空闲教室查询、图书馆座位预约和校园热力图集中在这里。")

            ToolEntryCard(title: "空闲教室", subtitle: "筛选选定时段空教室", icon: "building.2.crop.circle") {
                openRoute(.emptyClassroom)
            }

            ToolEntryCard(title: "图书馆座位预约", subtitle: "跳转链接", icon: "chair.lounge") {
                browserItem = LibrarySeatReservationBrowserItem(url: LeafyExternalLinks.librarySeat)
            }

            ToolEntryCard(title: "校园热力图", subtitle: "查看当前教学楼拥挤度", icon: "map.fill") {
                openRoute(.campusHeatmap)
            }

        }
        .sheet(item: $browserItem) { item in
            LeafySafariView(url: item.url)
        }
    }
}

struct SportsSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("体育", subtitle: isCustomCampus ? "本地记录阳光长跑和体测，可按学校要求自定义长跑规则。" : "阳光长跑、体测和场馆开放集中管理。")

            ToolEntryCard(title: "阳光长跑", subtitle: isCustomCampus ? "自定义目标次数、周期和假期周规则" : "每两周四次，满分 34 次", icon: "figure.run") {
                openRoute(.sunshineRun)
            }

            ToolEntryCard(title: "体测记录", subtitle: "记录体测项目、成绩和趋势", icon: "figure.strengthtraining.traditional") {
                openRoute(.fitnessTestRecords)
            }

            if !isCustomCampus {
                ToolEntryCard(title: "场馆开放", subtitle: "场馆开放时间与预约方式", icon: "sportscourt") {
                    openRoute(.sportsVenues)
                }
            }
        }
    }
}

struct ToolEntryCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LeafyIconBadge(systemName: icon)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(title, language: leafyLanguage))
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.text(subtitle, language: leafyLanguage))
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(18)
            .leafyCardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct LeafySafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}


private struct LibrarySeatReservationBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}
