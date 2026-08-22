import Foundation
import Supabase

extension CommunityService {
    func notificationEvents(profileID: UUID) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            let subscriptionTask = Task {
                do {
                    try await ensureAnonymousSession()
                    try Task.checkCancellation()

                    let client = try LeafySupabase.shared.requireClient()
                    let channel = client.realtimeV2.channel(
                        "community-notifications-\(profileID.uuidString)-\(UUID().uuidString)"
                    )
                    let filter = RealtimePostgresFilter.eq("recipient_id", value: profileID)
                    let inserts = channel.postgresChange(
                        InsertAction.self,
                        table: "community_notifications",
                        filter: filter
                    )
                    let updates = channel.postgresChange(
                        UpdateAction.self,
                        table: "community_notifications",
                        filter: filter
                    )

                    let insertTask = Task {
                        for await _ in inserts {
                            guard !Task.isCancelled else { return }
                            continuation.yield(())
                        }
                    }
                    let updateTask = Task {
                        for await _ in updates {
                            guard !Task.isCancelled else { return }
                            continuation.yield(())
                        }
                    }

                    defer {
                        insertTask.cancel()
                        updateTask.cancel()
                        Task {
                            await client.realtimeV2.removeChannel(channel)
                        }
                    }

                    try await channel.subscribeWithError()
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(60))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                subscriptionTask.cancel()
            }
        }
    }

    func feedEvents(campusID: String) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            let subscriptionTask = Task {
                do {
                    try await ensureAnonymousSession()
                    try Task.checkCancellation()

                    let client = try LeafySupabase.shared.requireClient()
                    let channel = client.realtimeV2.channel(
                        "community-feed-\(campusID)-\(UUID().uuidString)"
                    )
                    let filter = RealtimePostgresFilter.eq("campus_id", value: campusID)
                    let postInserts = channel.postgresChange(
                        InsertAction.self,
                        table: "posts",
                        filter: filter
                    )
                    let postUpdates = channel.postgresChange(
                        UpdateAction.self,
                        table: "posts",
                        filter: filter
                    )
                    let pollInserts = channel.postgresChange(
                        InsertAction.self,
                        table: "community_polls",
                        filter: filter
                    )
                    let pollUpdates = channel.postgresChange(
                        UpdateAction.self,
                        table: "community_polls",
                        filter: filter
                    )

                    let postInsertTask = Task {
                        for await action in postInserts where action.record.isPublishedCommunityFeedRecord {
                            guard !Task.isCancelled else { return }
                            continuation.yield(())
                        }
                    }
                    let postUpdateTask = Task {
                        for await action in postUpdates where action.record.isPublishedCommunityFeedRecord {
                            guard !Task.isCancelled else { return }
                            continuation.yield(())
                        }
                    }
                    let pollInsertTask = Task {
                        for await action in pollInserts where action.record.isPublishedCommunityFeedRecord {
                            guard !Task.isCancelled else { return }
                            continuation.yield(())
                        }
                    }
                    let pollUpdateTask = Task {
                        for await action in pollUpdates where action.record.isPublishedCommunityFeedRecord {
                            guard !Task.isCancelled else { return }
                            continuation.yield(())
                        }
                    }

                    defer {
                        postInsertTask.cancel()
                        postUpdateTask.cancel()
                        pollInsertTask.cancel()
                        pollUpdateTask.cancel()
                        Task {
                            await client.realtimeV2.removeChannel(channel)
                        }
                    }

                    try await channel.subscribeWithError()
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(60))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                subscriptionTask.cancel()
            }
        }
    }
}

private extension JSONObject {
    nonisolated var isPublishedCommunityFeedRecord: Bool {
        self["status"]?.stringValue == "published"
    }
}
