import Foundation

@MainActor
struct LearningWorkspaceIndex {
    static let empty = LearningWorkspaceIndex(
        summariesByDestinationID: [:],
        materialsByDestinationID: [:],
        tasksByDestinationID: [:],
        recordsByDestinationID: [:]
    )

    private let summariesByDestinationID: [String: LearningWorkspaceSummary]
    private let materialsByDestinationID: [String: [LearningMaterialDocument]]
    private let tasksByDestinationID: [String: [LearningProjectTask]]
    private let recordsByDestinationID: [String: [StudyTimeRecord]]

    static func make(
        materials: [LearningMaterialDocument],
        tasks: [LearningProjectTask],
        records: [StudyTimeRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LearningWorkspaceIndex {
        let materialsByDestinationID = Dictionary(grouping: materials, by: destinationID(for:))
        let tasksByDestinationID = Dictionary(grouping: tasks, by: destinationID(for:)).mapValues { tasks in
            tasks.sorted(by: taskSort)
        }
        let recordsByDestinationID = Dictionary(grouping: records, by: destinationID(for:))
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let destinationIDs = Set(materialsByDestinationID.keys)
            .union(tasksByDestinationID.keys)
            .union(recordsByDestinationID.keys)

        let summariesByDestinationID = Dictionary(uniqueKeysWithValues: destinationIDs.map { destinationID in
            let scopedMaterials = materialsByDestinationID[destinationID] ?? []
            let scopedTasks = tasksByDestinationID[destinationID] ?? []
            let scopedRecords = recordsByDestinationID[destinationID] ?? []
            return (
                destinationID,
                LearningWorkspaceSummary(
                    materialCount: scopedMaterials.count,
                    taskCount: scopedTasks.count,
                    completedTaskCount: scopedTasks.filter(\.isCompleted).count,
                    recordCount: scopedRecords.count,
                    totalDuration: scopedRecords.learningDuration,
                    weekDuration: scopedRecords.filter { record in
                        week?.contains(record.startedAt) == true
                    }.learningDuration
                )
            )
        })

        return LearningWorkspaceIndex(
            summariesByDestinationID: summariesByDestinationID,
            materialsByDestinationID: materialsByDestinationID,
            tasksByDestinationID: tasksByDestinationID,
            recordsByDestinationID: recordsByDestinationID
        )
    }

    func summary(for destination: LearningWorkspaceDestination) -> LearningWorkspaceSummary {
        summariesByDestinationID[destination.id] ?? .empty
    }

    func materials(for destination: LearningWorkspaceDestination) -> [LearningMaterialDocument] {
        materialsByDestinationID[destination.id] ?? []
    }

    func tasks(for destination: LearningWorkspaceDestination) -> [LearningProjectTask] {
        tasksByDestinationID[destination.id] ?? []
    }

    func records(for destination: LearningWorkspaceDestination) -> [StudyTimeRecord] {
        recordsByDestinationID[destination.id] ?? []
    }

    private static func destinationID(for material: LearningMaterialDocument) -> String {
        destinationID(projectID: material.projectID, category: material.category)
    }

    private static func destinationID(for task: LearningProjectTask) -> String {
        destinationID(projectID: task.projectID, category: task.category)
    }

    private static func destinationID(for record: StudyTimeRecord) -> String {
        destinationID(projectID: record.projectID, category: record.category)
    }

    private static func destinationID(projectID: String, category: LearningMaterialCategory) -> String {
        let trimmedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedProjectID.isEmpty else { return "project-\(trimmedProjectID)" }
        return LearningWorkspaceDestination.fixed(category).id
    }

    private static func taskSort(_ lhs: LearningProjectTask, _ rhs: LearningProjectTask) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (lhsDate?, rhsDate?):
            return lhsDate < rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

@MainActor
struct LearningWorkspaceIndexSignature: Equatable {
    private let materialItems: [MaterialItem]
    private let taskItems: [TaskItem]
    private let recordItems: [RecordItem]

    init(
        materials: [LearningMaterialDocument] = [],
        tasks: [LearningProjectTask] = [],
        records: [StudyTimeRecord] = []
    ) {
        materialItems = materials.map(MaterialItem.init(material:))
        taskItems = tasks.map(TaskItem.init(task:))
        recordItems = records.map(RecordItem.init(record:))
    }

    private struct MaterialItem: Equatable {
        let id: UUID
        let projectID: String
        let categoryRawValue: String
        let updatedAt: Date

        init(material: LearningMaterialDocument) {
            id = material.id
            projectID = material.projectID
            categoryRawValue = material.categoryRawValue
            updatedAt = material.updatedAt
        }
    }

    private struct TaskItem: Equatable {
        let id: UUID
        let projectID: String
        let categoryRawValue: String
        let dueAt: Date?
        let isCompleted: Bool
        let updatedAt: Date

        init(task: LearningProjectTask) {
            id = task.id
            projectID = task.projectID
            categoryRawValue = task.categoryRawValue
            dueAt = task.dueAt
            isCompleted = task.isCompleted
            updatedAt = task.updatedAt
        }
    }

    private struct RecordItem: Equatable {
        let id: UUID
        let projectID: String
        let categoryRawValue: String
        let startedAt: Date
        let endedAt: Date
        let updatedAt: Date

        init(record: StudyTimeRecord) {
            id = record.id
            projectID = record.projectID
            categoryRawValue = record.categoryRawValue
            startedAt = record.startedAt
            endedAt = record.endedAt
            updatedAt = record.updatedAt
        }
    }
}
