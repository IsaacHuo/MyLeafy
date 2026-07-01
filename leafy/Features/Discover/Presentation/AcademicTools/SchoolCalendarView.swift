import SafariServices
import SwiftUI

struct SchoolCalendarView: View {
    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var selectedAsset: CalendarAsset?

    var body: some View {
        let assets = networkManager.calendarAssets()

        AcademicDetailScrollContainer(spacing: 16) {
            ForEach(assets) { asset in
                Button {
                    selectedAsset = asset
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.title)
                                .font(.headline)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(asset.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "safari")
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("校历")
        .leafyInlineNavigationTitle()
        .sheet(item: $selectedAsset) { asset in
            SchoolCalendarSafariView(url: previewPageURL(for: asset))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func previewPageURL(for asset: CalendarAsset) -> URL {
        if asset.id == "calendar" {
            return URL(string: "https://myleafy.space/campus/calendar/")!
        }
        return URL(string: "https://myleafy.space/campus/timetable/")!
    }
}

#if canImport(UIKit)
private struct SchoolCalendarSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
private typealias SchoolCalendarSafariView = LeafyExternalBrowserView
#endif
