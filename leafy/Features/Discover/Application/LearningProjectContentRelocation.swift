import Foundation
import SwiftData

enum LearningProjectContentRelocation {
    static func deleteContents(
        in destination: LearningWorkspaceDestination,
        materials: [LearningMaterialDocument],
        tasks: [LearningProjectTask],
        records: [StudyTimeRecord],
        modelContext: ModelContext
    ) throws {
        let scopedMaterials = materials.filter { $0.belongs(to: destination) }
        let scopedTasks = tasks.filter { $0.belongs(to: destination) }
        let scopedRecords = records.filter { $0.belongs(to: destination) }

        let files = scopedMaterials.compactMap { material in
            LearningMaterialFileStore.fileURL(for: material).map { LocalFileCleanup.File(material, url: $0) }
        }
        let models: [any PersistentModel] = scopedMaterials + scopedTasks + scopedRecords
        try LocalFileCleanup().delete(models, files: files, in: modelContext)
    }

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
        updatedAt: Date = Date(),
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let id = project.id.uuidString
        let materialSnapshots = materials.filter { $0.projectID == id }.map { (
            $0,
            $0.projectID,
            $0.categoryRawValue,
            $0.updatedAt
        ) }
        let taskSnapshots = tasks.filter { $0.projectID == id }.map { (
            $0,
            $0.projectID,
            $0.categoryRawValue,
            $0.updatedAt
        ) }
        let recordSnapshots = records.filter { $0.projectID == id }.map { (
            $0,
            $0.projectID,
            $0.categoryRawValue,
            $0.updatedAt
        ) }
        moveToUnfiled(
            projectID: project.id,
            materials: materials,
            tasks: tasks,
            records: records,
            updatedAt: updatedAt
        )
        modelContext.delete(project)
        try LocalModelSave.save(modelContext, undo: {
            modelContext.insert(project)
            for (record, projectID, category, date) in materialSnapshots {
                record.projectID = projectID; record.categoryRawValue = category; record.updatedAt = date
            }
            for (record, projectID, category, date) in taskSnapshots {
                record.projectID = projectID; record.categoryRawValue = category; record.updatedAt = date
            }
            for (record, projectID, category, date) in recordSnapshots {
                record.projectID = projectID; record.categoryRawValue = category; record.updatedAt = date
            }
        }, using: save)
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

        let files = scopedMaterials.compactMap { material in
            LearningMaterialFileStore.fileURL(for: material).map { LocalFileCleanup.File(material, url: $0) }
        }
        let scopedTasks = tasks.filter { $0.projectID == projectIDString }
        let scopedRecords = records.filter { $0.projectID == projectIDString }
        let models: [any PersistentModel] = [project] + scopedMaterials + scopedTasks + scopedRecords
        try LocalFileCleanup().delete(models, files: files, in: modelContext)
    }
}
