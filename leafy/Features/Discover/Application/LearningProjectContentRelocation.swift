import Foundation
import SwiftData

enum LearningProjectContentRelocation {
    static func moveToUnfiled(
        projectID: UUID,
        materials: [LearningMaterialDocument],
        tasks: [LearningProjectTask],
        records: [StudyTimeRecord],
        updatedAt: Date = Date()
    ) {
        let projectIDString = projectID.uuidString

        for material in materials where material.projectID == projectIDString {
            material.projectID = ""
            material.category = .other
            material.updatedAt = updatedAt
        }

        for task in tasks where task.projectID == projectIDString {
            task.projectID = ""
            task.category = .other
            task.updatedAt = updatedAt
        }

        for record in records where record.projectID == projectIDString {
            record.projectID = ""
            record.category = .other
            record.updatedAt = updatedAt
        }
    }

    static func deleteProjectKeepingContents(
        _ project: LearningProject,
        materials: [LearningMaterialDocument],
        tasks: [LearningProjectTask],
        records: [StudyTimeRecord],
        modelContext: ModelContext,
        updatedAt: Date = Date()
    ) throws {
        moveToUnfiled(
            projectID: project.id,
            materials: materials,
            tasks: tasks,
            records: records,
            updatedAt: updatedAt
        )
        modelContext.delete(project)
        try modelContext.save()
    }

    static func deleteProjectAndContents(
        _ project: LearningProject,
        materials: [LearningMaterialDocument],
        tasks: [LearningProjectTask],
        records: [StudyTimeRecord],
        modelContext: ModelContext
    ) throws {
        let projectIDString = project.id.uuidString
        let scopedMaterials = materials.filter { $0.projectID == projectIDString }

        for material in scopedMaterials {
            try LearningMaterialFileStore.deleteFile(named: material.localFilename)
        }

        for material in scopedMaterials {
            modelContext.delete(material)
        }

        for task in tasks where task.projectID == projectIDString {
            modelContext.delete(task)
        }

        for record in records where record.projectID == projectIDString {
            modelContext.delete(record)
        }

        modelContext.delete(project)
        try modelContext.save()
    }
}
