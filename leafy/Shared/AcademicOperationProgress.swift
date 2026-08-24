import SwiftUI

nonisolated enum AcademicOperationKind: String, Equatable, Sendable {
    case timetable
    case allAcademicData
    case grades
    case teachingAndCultivation
    case exams
    case rankings
    case emptyClassrooms
    case campusHeatmap

    var title: String {
        switch self {
        case .timetable:
            return "同步课表"
        case .allAcademicData:
            return "同步教务数据"
        case .grades:
            return "同步成绩"
        case .teachingAndCultivation:
            return "同步教学与培养"
        case .exams:
            return "同步考试安排"
        case .rankings:
            return "同步官方排名"
        case .emptyClassrooms:
            return "查询教室"
        case .campusHeatmap:
            return "更新校园热力图"
        }
    }

    var allowedStages: Set<AcademicOperationStage> {
        let authentication: Set<AcademicOperationStage> = [
            .connectingAcademicSystem,
            .refreshingCaptcha,
            .recognizingCaptcha,
            .authenticating
        ]
        switch self {
        case .timetable:
            return authentication.union([
                .refreshingSemester, .fetchingTimetable, .processingTimetable, .savingTimetable
            ])
        case .allAcademicData:
            return authentication.union([
                .refreshingSemester,
                .fetchingTimetable, .processingTimetable, .savingTimetable,
                .fetchingGrades, .processingGrades, .savingGrades,
                .fetchingRankings,
                .fetchingExams, .processingExams,
                .fetchingTeachingPlan, .processingTeachingPlan,
                .fetchingTrainingProgram, .processingTrainingProgram,
                .savingResults
            ])
        case .grades:
            return authentication.union([.fetchingGrades, .processingGrades, .savingGrades])
        case .teachingAndCultivation:
            return authentication.union([
                .fetchingTeachingPlan, .processingTeachingPlan,
                .fetchingTrainingProgram, .processingTrainingProgram
            ])
        case .exams:
            return authentication.union([.fetchingExams, .processingExams])
        case .rankings:
            return authentication.union([.fetchingRankings])
        case .emptyClassrooms:
            return authentication.union([.queryingEmptyClassrooms, .queryingClassroomUsage, .queryCompleted])
        case .campusHeatmap:
            return authentication.union([.queryingEmptyClassrooms, .generatingHeatmap, .queryCompleted])
        }
    }
}

nonisolated enum AcademicOperationStage: String, Equatable, Hashable, Sendable {
    case connectingAcademicSystem
    case refreshingCaptcha
    case recognizingCaptcha
    case authenticating
    case refreshingSemester
    case fetchingTimetable
    case processingTimetable
    case savingTimetable
    case fetchingGrades
    case processingGrades
    case savingGrades
    case fetchingRankings
    case fetchingExams
    case processingExams
    case fetchingTeachingPlan
    case processingTeachingPlan
    case fetchingTrainingProgram
    case processingTrainingProgram
    case savingResults
    case queryingEmptyClassrooms
    case queryingClassroomUsage
    case generatingHeatmap
    case queryCompleted

    var message: String {
        switch self {
        case .connectingAcademicSystem:
            return "正在连接教务系统"
        case .refreshingCaptcha:
            return "正在刷新验证码"
        case .recognizingCaptcha:
            return "正在识别验证码"
        case .authenticating:
            return "正在验证登录"
        case .refreshingSemester:
            return "正在更新学期信息"
        case .fetchingTimetable:
            return "正在拉取课表"
        case .processingTimetable:
            return "正在处理课表"
        case .savingTimetable:
            return "正在保存课表"
        case .fetchingGrades:
            return "正在拉取成绩"
        case .processingGrades:
            return "正在处理成绩"
        case .savingGrades:
            return "正在保存成绩"
        case .fetchingRankings:
            return "正在拉取官方排名"
        case .fetchingExams:
            return "正在拉取考试安排"
        case .processingExams:
            return "正在处理考试安排"
        case .fetchingTeachingPlan:
            return "正在拉取教学计划"
        case .processingTeachingPlan:
            return "正在处理教学计划"
        case .fetchingTrainingProgram:
            return "正在拉取培养方案"
        case .processingTrainingProgram:
            return "正在处理培养方案"
        case .savingResults:
            return "正在保存同步结果"
        case .queryingEmptyClassrooms:
            return "正在查询空教室"
        case .queryingClassroomUsage:
            return "正在查询教室占用"
        case .generatingHeatmap:
            return "正在生成校园热力图"
        case .queryCompleted:
            return "查询完成"
        }
    }
}

nonisolated enum AcademicOperationStepStatus: Equatable, Sendable {
    case running
    case completed
    case failed(String)
}

nonisolated struct AcademicOperationStep: Equatable, Identifiable, Sendable {
    let id: String
    let stage: AcademicOperationStage
    let detail: String?
    var status: AcademicOperationStepStatus
}

nonisolated struct AcademicOperationProgress: Equatable, Sendable {
    let kind: AcademicOperationKind
    var steps: [AcademicOperationStep] = []

    var currentStage: AcademicOperationStage? {
        steps.last(where: { $0.status == .running })?.stage
    }
}

nonisolated enum AcademicOperationProgressEvent: Equatable, Sendable {
    case begin(AcademicOperationStage)
    case beginAttempt(AcademicOperationStage, current: Int, total: Int)
    case fail(AcademicOperationStage, String)
}

typealias AcademicOperationProgressReporter = @MainActor @Sendable (AcademicOperationProgressEvent) -> Void

@MainActor
@Observable
final class AcademicOperationProgressController {
    private(set) var progress: AcademicOperationProgress?

    var isActive: Bool { progress != nil }

    func begin(_ kind: AcademicOperationKind) {
        if progress?.kind != kind {
            progress = AcademicOperationProgress(kind: kind)
        }
    }

    func reporter(for kind: AcademicOperationKind) -> AcademicOperationProgressReporter {
        { [weak self] event in
            self?.record(event, for: kind)
        }
    }

    func record(_ event: AcademicOperationProgressEvent, for kind: AcademicOperationKind) {
        begin(kind)
        guard var progress else { return }

        let stage: AcademicOperationStage
        switch event {
        case .begin(let eventStage),
             .beginAttempt(let eventStage, _, _),
             .fail(let eventStage, _):
            stage = eventStage
        }
        guard kind.allowedStages.contains(stage) else { return }

        switch event {
        case .begin(let stage):
            beginStep(
                id: stage.rawValue,
                stage: stage,
                detail: nil,
                progress: &progress
            )
        case .beginAttempt(let stage, let current, let total):
            beginStep(
                id: "\(stage.rawValue).\(current)",
                stage: stage,
                detail: "第 \(current)/\(total) 次",
                progress: &progress
            )
        case .fail(let stage, let message):
            if let runningIndex = progress.steps.lastIndex(where: { $0.status == .running }) {
                progress.steps[runningIndex].status = .failed(message)
            } else if let existingIndex = progress.steps.lastIndex(where: { $0.stage == stage }) {
                progress.steps[existingIndex].status = .failed(message)
            } else {
                progress.steps.append(
                    AcademicOperationStep(
                        id: stage.rawValue,
                        stage: stage,
                        detail: nil,
                        status: .failed(message)
                    )
                )
            }
        }

        self.progress = progress
    }

    private func beginStep(
        id: String,
        stage: AcademicOperationStage,
        detail: String?,
        progress: inout AcademicOperationProgress
    ) {
            if let runningIndex = progress.steps.lastIndex(where: { $0.status == .running }) {
                progress.steps[runningIndex].status = .completed
            }
            if let existingIndex = progress.steps.firstIndex(where: { $0.id == id }) {
                var step = progress.steps.remove(at: existingIndex)
                step = AcademicOperationStep(
                    id: id,
                    stage: stage,
                    detail: detail,
                    status: .running
                )
                progress.steps.append(step)
            } else {
                progress.steps.append(
                    AcademicOperationStep(
                        id: id,
                        stage: stage,
                        detail: detail,
                        status: .running
                    )
                )
            }
    }

    func completeCurrentStep() {
        guard var progress,
              let runningIndex = progress.steps.lastIndex(where: { $0.status == .running }) else {
            return
        }
        progress.steps[runningIndex].status = .completed
        self.progress = progress
    }

    func clear() {
        progress = nil
    }
}

extension View {
    func academicOperationProgress(_ controller: AcademicOperationProgressController) -> some View {
        modifier(AcademicOperationProgressModifier(controller: controller))
    }
}

private struct AcademicOperationProgressModifier: ViewModifier {
    @Bindable var controller: AcademicOperationProgressController

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress = controller.progress {
                    ZStack {
                        Color.black.opacity(0.1)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {}

                        AcademicOperationProgressCard(progress: progress)
                            .padding(AppSpacing.page)
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controller.progress)
    }
}

private struct AcademicOperationProgressCard: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage

    let progress: AcademicOperationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * leafyControlScale) {
            Text(L10n.text(progress.kind.title, language: leafyLanguage))
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10 * leafyControlScale) {
                    ForEach(progress.steps) { step in
                        stepRow(step)
                    }
                }
            }
            .frame(maxHeight: 420 * leafyControlScale)
        }
        .frame(maxWidth: 220 * leafyControlScale, alignment: .leading)
        .padding(AppSpacing.card)
        .leafyCardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func stepRow(_ step: AcademicOperationStep) -> some View {
        HStack(alignment: .top, spacing: 10 * leafyControlScale) {
            statusIcon(for: step.status)
                .frame(width: 20 * leafyControlScale, height: 20 * leafyControlScale)

            VStack(alignment: .leading, spacing: 3 * leafyControlScale) {
                Text(L10n.text(step.stage.message, language: leafyLanguage))
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)

                if let detail = step.detail {
                    Text(detail)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if case .failed(let message) = step.status {
                    Text(message)
                        .microCaption()
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: AcademicOperationStepStatus) -> some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
        }
    }

    private var accessibilitySummary: String {
        let current = progress.currentStage?.message ?? progress.steps.last?.stage.message ?? ""
        return L10n.text(
            "%@，%@",
            language: leafyLanguage,
            L10n.text(progress.kind.title, language: leafyLanguage),
            L10n.text(current, language: leafyLanguage)
        )
    }
}
