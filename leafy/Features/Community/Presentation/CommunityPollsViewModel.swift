import Combine
import Foundation
import OSLog

@MainActor
final class CommunityPollsViewModel: ObservableObject {
    @Published private(set) var polls: [CommunityPoll] = []
    @Published private(set) var isLoading = false
    @Published private(set) var activePollIDs: Set<UUID> = []
    @Published var errorMessage: String?

    private let repository: any CommunityPollRepository

    init(repository: any CommunityPollRepository = LiveCommunityRepository()) {
        self.repository = repository
    }

    func load() async {
        CommunityDiagnostics.log.info("Community polls load started")
        isLoading = true
        defer { isLoading = false }

        do {
            try await CommunityTimeout.run(
                seconds: 10,
                message: L10n.text("社区会话建立超时，请检查网络后重试。")
            ) { [repository] in
                try await repository.ensureAnonymousSession()
            }

            let loadedPolls = try await CommunityTimeout.run(
                seconds: 10,
                message: L10n.text("投票加载超时，请检查网络后重试。")
            ) { [repository] in
                try await repository.fetchPolls(limit: 30)
            }

            polls = loadedPolls
            errorMessage = nil
            CommunityDiagnostics.log.info("Community polls load finished with \(loadedPolls.count) polls")
        } catch {
            CommunityDiagnostics.log.error("Community polls load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func createPoll(input: CreatePollInput) async -> Bool {
        if let validationError = input.validationError {
            errorMessage = L10n.text(validationError)
            return false
        }

        do {
            let poll = try await repository.createPoll(input: input)
            polls.insert(poll, at: 0)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func vote(pollID: UUID, optionID: UUID) async -> Bool {
        guard !activePollIDs.contains(pollID) else { return false }
        activePollIDs.insert(pollID)
        defer { activePollIDs.remove(pollID) }

        do {
            let updatedPoll = try await repository.votePoll(pollID: pollID, optionID: optionID)
            replacePoll(updatedPoll)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestDeletion(poll: CommunityPoll, reason: String?) async -> Bool {
        guard !activePollIDs.contains(poll.id) else { return false }
        activePollIDs.insert(poll.id)
        defer { activePollIDs.remove(poll.id) }

        do {
            let updatedPoll = try await repository.requestPollDeletion(pollID: poll.id, reason: reason)
            replacePoll(updatedPoll)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func replacePoll(_ poll: CommunityPoll) {
        if let index = polls.firstIndex(where: { $0.id == poll.id }) {
            polls[index] = poll
        } else {
            polls.insert(poll, at: 0)
        }
    }
}
