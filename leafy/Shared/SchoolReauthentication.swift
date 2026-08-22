import SwiftUI
import UIKit

nonisolated enum SchoolReauthentication {
    static func requiresReauthentication(_ error: Error) -> Bool {
        if case SchoolNetworkError.sessionExpired = error {
            return true
        }

        if let urlError = error as? URLError {
            return urlError.code == .userAuthenticationRequired
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain &&
            nsError.code == URLError.userAuthenticationRequired.rawValue
    }

    static func shouldPromptForUserInitiatedAccess(_ error: Error) -> Bool {
        requiresReauthentication(error)
    }

    @MainActor
    static func preflightRequest(
        networkManager: SchoolNetworkManager,
        context: SchoolReauthenticationContext,
        allowsAutomaticAttempt: Bool = true
    ) -> SchoolReauthenticationRequest? {
        guard networkManager.hasCachedIdentity, !networkManager.isLoggedIn else {
            return nil
        }
        return SchoolReauthenticationRequest(
            context: context,
            allowsAutomaticAttempt: allowsAutomaticAttempt
        )
    }
}

struct SchoolReauthenticationContext: Equatable {
    let portal: SchoolPortal
    let title: String
    let message: String
    let submitTitle: String

    static func timetable(portal: SchoolPortal) -> SchoolReauthenticationContext {
        SchoolReauthenticationContext(
            portal: portal,
            title: "重新登录教务",
            message: "当前教务登录状态已失效，验证后会继续刷新课表。",
            submitTitle: "继续刷新课表"
        )
    }

    static let grades = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，验证后会继续刷新成绩。",
        submitTitle: "继续刷新成绩"
    )

    static let examSchedule = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，验证后会继续刷新考试安排。",
        submitTitle: "继续刷新考试"
    )

    static let teachingPlan = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，验证后会继续刷新教学计划。",
        submitTitle: "继续刷新计划"
    )

    static let trainingProgram = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，验证后会继续刷新培养方案。",
        submitTitle: "继续刷新方案"
    )

    static let emptyClassrooms = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，验证后会继续刚才的空教室查询。",
        submitTitle: "继续查询"
    )

    static let campusHeatmap = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "验证后会获取所选日期和节次的空闲教室数据。",
        submitTitle: "继续更新数据"
    )

    static let schoolDataSync = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，验证后会继续本次同步。",
        submitTitle: "继续同步"
    )
}

struct SchoolReauthenticationRequest: Identifiable {
    let id = UUID()
    let context: SchoolReauthenticationContext
    let allowsAutomaticAttempt: Bool

    init(
        context: SchoolReauthenticationContext,
        allowsAutomaticAttempt: Bool = true
    ) {
        self.context = context
        self.allowsAutomaticAttempt = allowsAutomaticAttempt
    }
}

enum SchoolReauthenticationMethod: Equatable {
    case automatic
    case manual
}

struct SchoolReauthenticationCompletion {
    let context: SchoolReauthenticationContext
    let method: SchoolReauthenticationMethod
}

extension View {
    func schoolReauthenticationSheet(
        request: Binding<SchoolReauthenticationRequest?>,
        networkManager: SchoolNetworkManager,
        onAuthenticated: @escaping (SchoolReauthenticationCompletion) -> Void
    ) -> some View {
        modifier(
            SchoolReauthenticationModifier(
                request: request,
                networkManager: networkManager,
                onAuthenticated: onAuthenticated
            )
        )
    }
}

private struct SchoolManualReauthenticationPresentation: Identifiable {
    let id = UUID()
    let context: SchoolReauthenticationContext
    let challenge: SchoolCaptchaChallenge?
    let initialMessage: String?
}

private struct SchoolReauthenticationModifier: ViewModifier {
    @Binding var request: SchoolReauthenticationRequest?
    @ObservedObject var networkManager: SchoolNetworkManager
    let onAuthenticated: (SchoolReauthenticationCompletion) -> Void

    @State private var isRecovering = false
    @State private var manualPresentation: SchoolManualReauthenticationPresentation?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isRecovering {
                    ZStack {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()

                        ProgressView("正在连接教务系统…")
                            .padding(.horizontal, 22)
                            .padding(.vertical, 18)
                            .leafyCardStyle()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .leafySheet(item: $manualPresentation) { presentation in
                SchoolReauthenticationSheet(
                    networkManager: networkManager,
                    presentation: presentation
                ) {
                    manualPresentation = nil
                    onAuthenticated(
                        SchoolReauthenticationCompletion(
                            context: presentation.context,
                            method: .manual
                        )
                    )
                }
                .presentationDetents([.large])
            }
            .task(id: request?.id) {
                guard let activeRequest = request else { return }
                await recover(activeRequest)
            }
    }

    @MainActor
    private func recover(_ activeRequest: SchoolReauthenticationRequest) async {
        isRecovering = true
        defer { isRecovering = false }

        let service = SchoolAuthenticationService(client: networkManager)
        do {
            let result = try await service.recover(
                portal: activeRequest.context.portal,
                allowsAutomaticAttempt: activeRequest.allowsAutomaticAttempt
            )
            guard !Task.isCancelled else { return }
            request = nil

            switch result {
            case .authenticated:
                onAuthenticated(
                    SchoolReauthenticationCompletion(
                        context: activeRequest.context,
                        method: .automatic
                    )
                )
            case .requiresManual(let challenge, let message):
                manualPresentation = SchoolManualReauthenticationPresentation(
                    context: activeRequest.context,
                    challenge: challenge,
                    initialMessage: message
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            request = nil
            manualPresentation = SchoolManualReauthenticationPresentation(
                context: activeRequest.context,
                challenge: nil,
                initialMessage: recoveryErrorMessage(error)
            )
        }
    }

    private func recoveryErrorMessage(_ error: Error) -> String {
        if case SchoolNetworkError.campusNetworkRequired = error {
            return "暂时无法连接教务系统。请连接 bjfu-wifi 或北林 VPN 后，点击验证码区域重试。"
        }
        return error.localizedDescription
    }
}

private struct SchoolReauthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage

    @ObservedObject private var networkManager: SchoolNetworkManager

    let presentation: SchoolManualReauthenticationPresentation
    let onAuthenticated: () -> Void

    @State private var account: String
    @State private var password: String
    @State private var challenge: SchoolCaptchaChallenge?
    @State private var captchaCode = ""
    @State private var isPasswordVisible = false
    @State private var showsCredentialFields: Bool
    @State private var isCaptchaLoading = false
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var prefilledAccount: String?

    private var canSubmit: Bool {
        !isLoggingIn &&
        challenge != nil &&
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !captchaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        networkManager: SchoolNetworkManager,
        presentation: SchoolManualReauthenticationPresentation,
        onAuthenticated: @escaping () -> Void
    ) {
        _networkManager = ObservedObject(wrappedValue: networkManager)
        let credential = presentation.challenge?.credential ?? SchoolLoginCredentialStore.load(
            campusID: networkManager.campusDescriptor.id,
            portal: presentation.context.portal
        )
        let authenticatedAccount = networkManager.authenticatedEduID ?? ""
        let matchingCredential = credential?.account == authenticatedAccount ? credential : nil
        _account = State(initialValue: matchingCredential?.account ?? authenticatedAccount)
        _password = State(initialValue: matchingCredential?.password ?? "")
        _challenge = State(initialValue: presentation.challenge)
        _showsCredentialFields = State(initialValue: matchingCredential == nil)
        _errorMessage = State(initialValue: presentation.initialMessage)
        _prefilledAccount = State(initialValue: matchingCredential?.account)
        self.presentation = presentation
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    header

                    if showsCredentialFields {
                        credentialFields
                    }

                    captchaField

                    if !showsCredentialFields {
                        Button("修改账号或密码") {
                            showsCredentialFields = true
                        }
                        .font(.subheadline)
                    }

                    if let errorMessage {
                        Text(L10n.text(errorMessage, language: leafyLanguage))
                            .leafyBody()
                            .foregroundStyle(AppTheme.danger)
                    }

                    submitButton
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text(presentation.context.portal.title, language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button(L10n.text("取消", language: leafyLanguage)) {
                        clearSensitiveFields()
                        dismiss()
                    }
                }
            }
            .onChange(of: account) { _, newValue in
                handleAccountChange(newValue)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(presentation.context.title, language: leafyLanguage))
                .leafyTitle3()
                .foregroundStyle(AppTheme.primaryText)
            Text(L10n.text(presentation.context.message, language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
            Text(L10n.text(presentation.context.portal.loginHint, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }

    private var credentialFields: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("学号", language: leafyLanguage), text: $account)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyUsernameContentType()
                .padding(.horizontal, 16 * leafyControlScale)
                .frame(height: 52 * leafyControlScale)

            Divider()
                .padding(.leading, 16 * leafyControlScale)

            HStack(spacing: 12) {
                Group {
                    if isPasswordVisible {
                        TextField(L10n.text("密码", language: leafyLanguage), text: $password)
                    } else {
                        SecureField(L10n.text("密码", language: leafyLanguage), text: $password)
                    }
                }
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyPasswordContentType()

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .frame(width: 34 * leafyControlScale, height: 34 * leafyControlScale)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityLabel(
                    isPasswordVisible
                        ? L10n.text("隐藏密码", language: leafyLanguage)
                        : L10n.text("显示密码", language: leafyLanguage)
                )
            }
            .padding(.horizontal, 16 * leafyControlScale)
            .frame(height: 52 * leafyControlScale)
        }
        .leafyCardStyle()
    }

    private var captchaField: some View {
        HStack(spacing: 12) {
            TextField(L10n.text("验证码", language: leafyLanguage), text: $captchaCode)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyOneTimeCodeContentType()

            Button {
                Task { await fetchCaptcha(resetError: true) }
            } label: {
                ZStack {
                    if let image = challenge?.image {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    } else if isCaptchaLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(width: 112 * leafyControlScale, height: 38 * leafyControlScale)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isCaptchaLoading)
            .leafyGlassSurface(
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous),
                isInteractive: true
            )
            .accessibilityLabel(L10n.text("刷新验证码", language: leafyLanguage))
        }
        .padding(.leading, 16 * leafyControlScale)
        .padding(.trailing, 14 * leafyControlScale)
        .frame(height: 52 * leafyControlScale)
        .leafyCardStyle()
    }

    private var submitButton: some View {
        Button {
            Task { await submitLogin() }
        } label: {
            HStack(spacing: 8) {
                if isLoggingIn {
                    ProgressView()
                        .tint(.white)
                }
                Text(L10n.text(presentation.context.submitTitle, language: leafyLanguage))
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

    private func handleAccountChange(_ newValue: String) {
        guard let prefilledAccount else { return }
        let normalizedAccount = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedAccount != prefilledAccount {
            self.prefilledAccount = nil
            password = ""
        }
    }

    @MainActor
    private func fetchCaptcha(resetError: Bool) async {
        guard !isCaptchaLoading else { return }
        isCaptchaLoading = true
        defer { isCaptchaLoading = false }

        do {
            challenge = try await SchoolAuthenticationService(client: networkManager)
                .fetchManualChallenge(portal: presentation.context.portal)
            captchaCode = ""
            if resetError {
                errorMessage = nil
            }
        } catch {
            challenge = nil
            if case SchoolNetworkError.campusNetworkRequired = error {
                errorMessage = L10n.text(
                    "暂时无法连接教务验证码。请先连接 bjfu-wifi 或北林 VPN，再点击验证码区域重试。",
                    language: leafyLanguage
                )
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func submitLogin() async {
        guard canSubmit, let challenge else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let didLogin = try await SchoolAuthenticationService(client: networkManager).submitManual(
                challenge: challenge,
                account: account,
                password: password,
                captcha: captchaCode
            )

            guard didLogin else {
                showsCredentialFields = true
                errorMessage = L10n.text("登录请求已发送，但未能确认登录成功。请重试。", language: leafyLanguage)
                captchaCode = ""
                await fetchCaptcha(resetError: false)
                return
            }

            networkManager.isLoggedIn = true
            clearSensitiveFields()
            dismiss()
            onAuthenticated()
        } catch {
            showsCredentialFields = true
            errorMessage = error.localizedDescription
            captchaCode = ""
            await fetchCaptcha(resetError: false)
        }
    }

    private func clearSensitiveFields() {
        password = ""
        captchaCode = ""
        challenge = nil
    }
}
