import SwiftUI
import UIKit

extension ToolbarItemPlacement {
    static var leafyLeading: ToolbarItemPlacement {
        .topBarLeading
    }

    static var leafyTrailing: ToolbarItemPlacement {
        .topBarTrailing
    }

    static var leafyKeyboard: ToolbarItemPlacement {
        .keyboard
    }
}

extension View {
    @ViewBuilder
    func leafyInsetGroupedListStyle() -> some View {
        listStyle(.insetGrouped)
    }

    @ViewBuilder
    func leafyCompactListSectionSpacing() -> some View {
        listSectionSpacing(.compact)
    }

    @ViewBuilder
    func leafyDisableAutocapitalization() -> some View {
        textInputAutocapitalization(.never)
    }

    @ViewBuilder
    func leafyUppercaseAutocapitalization() -> some View {
        textInputAutocapitalization(.characters)
    }

    @ViewBuilder
    func leafyUsernameContentType() -> some View {
        textContentType(.username)
    }

    @ViewBuilder
    func leafyPasswordContentType() -> some View {
        textContentType(.password)
    }

    @ViewBuilder
    func leafyOneTimeCodeContentType() -> some View {
        textContentType(.oneTimeCode)
    }

    @ViewBuilder
    func leafyInlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .leafyTranslucentNavigationBar()
    }

    @ViewBuilder
    func leafyTranslucentNavigationBar() -> some View {
        if #available(iOS 26.0, *) {
            toolbarBackground(.hidden, for: .navigationBar)
        } else {
            toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    func leafyNavigationBarHidden() -> some View {
        toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    func leafyNavigationBarVisible() -> some View {
        toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    func leafyNavigationToolbarBackgroundHidden() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    func leafyFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, content: content)
    }

    @ViewBuilder
    func leafyImagePreviewTabStyle(showsIndex: Bool) -> some View {
        tabViewStyle(.page(indexDisplayMode: showsIndex ? .always : .never))
    }
}

enum LeafyDeviceInfo {
    static var model: String {
        UIDevice.current.model
    }

    static var systemDescription: String {
        "iOS \(UIDevice.current.systemVersion)"
    }
}

enum LeafyClipboard {
    static var string: String? {
        get {
            UIPasteboard.general.string
        }
        set {
            UIPasteboard.general.string = newValue
        }
    }
}

enum LeafySystemSettings {
    static func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
