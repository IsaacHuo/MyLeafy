import Foundation
import os
import WidgetKit

protocol WidgetSnapshotPublishing: Sendable {
    func publish(_ archive: LeafyWidgetSnapshotArchive) async
    func publishNeedsLogin(_ archive: LeafyWidgetSnapshotArchive) async
}

actor WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    static let shared = WidgetSnapshotPublisher()
    private var lastSignature: WidgetSnapshotSignature?
    private var latestGeneratedAt = Date.distantPast

    func publish(_ archive: LeafyWidgetSnapshotArchive) async { publishIfChanged(archive) }
    func publishNeedsLogin(_ archive: LeafyWidgetSnapshotArchive) async { publishIfChanged(archive) }

    private func publishIfChanged(_ archive: LeafyWidgetSnapshotArchive) {
        // An older queued publish must never restore data after an identity reset.
        guard archive.generatedAt >= latestGeneratedAt else { return }
        latestGeneratedAt = archive.generatedAt
        let signature = WidgetSnapshotSignature(archive: archive)
        guard signature != lastSignature else { return }
        let state = LeafyPerformanceSignposter.widget.beginInterval("publish-snapshot")
        let didSave = LeafyWidgetSnapshotStore.save(archive)
        LeafyPerformanceSignposter.widget.endInterval("publish-snapshot", state)
        guard didSave else { return }
        lastSignature = signature
        WidgetCenter.shared.reloadTimelines(ofKind: LeafyWidgetConstants.widgetKind)
    }
}

struct WidgetSnapshotSignature: Equatable {
    private let content: LeafyWidgetSnapshotArchive

    nonisolated init(archive: LeafyWidgetSnapshotArchive) {
        var content = archive
        content.generatedAt = .distantPast
        self.content = content
    }
}
