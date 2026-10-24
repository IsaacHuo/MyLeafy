import Foundation
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var didStartImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = ExternalImportL10n.text("正在保存到 MyLeafy...")
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true

        doneButton.setTitle(ExternalImportL10n.text("完成"), for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(container)
        container.addSubview(stack)
        let preferredHeight = container.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        preferredHeight.priority = .defaultLow
        let minimumButtonHeight = doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        minimumButtonHeight.priority = UILayoutPriority(999) // UIStackView collapses the initially hidden button.

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            container.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            preferredHeight,
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            minimumButtonHeight
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartImport else { return }
        didStartImport = true

        Task {
            await importSharedItems()
        }
    }

    private func importSharedItems() async {
        var pendingBatch: (ExternalLearningMaterialImportStore, UUID)?
        do {
            let providers = itemProviders()
            guard !providers.isEmpty else {
                throw ExternalLearningMaterialImportError.emptyBatch
            }
            guard providers.count <= ExternalLearningMaterialImport.maximumItemCount else {
                throw ExternalLearningMaterialImportError.tooManyFiles
            }

            let store = try ExternalLearningMaterialImportStore.appGroupStore()
            let batchID = UUID()
            pendingBatch = (store, batchID)
            try store.prepareBatchDirectory(batchID)

            var items: [ExternalLearningMaterialImportItem] = []
            for provider in providers {
                let item = try await stageProvider(provider, store: store, batchID: batchID)
                items.append(item)
                guard items.reduce(Int64(0), { $0 + $1.byteCount }) <= ExternalLearningMaterialImport.maximumBatchBytes
                else {
                    throw ExternalLearningMaterialImportError.batchTooLarge
                }
            }

            guard !items.isEmpty else {
                throw ExternalLearningMaterialImportError.emptyBatch
            }

            let manifest = ExternalLearningMaterialImportManifest(
                id: batchID,
                source: .shareExtension,
                items: items
            )
            try store.writeManifest(manifest)
            pendingBatch = nil
            await openContainingApp(batchID: batchID)
        } catch {
            let reported = pendingBatch.map { $0.0.failure(error, cleaningBatch: $0.1) } ?? error
            showManualOpenMessage(reported.localizedDescription)
        }
    }

    private func itemProviders() -> [NSItemProvider] {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }
        return extensionItems.flatMap { $0.attachments ?? [] }
    }

    private func stageProvider(
        _ provider: NSItemProvider,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem {
        guard let typeIdentifier = supportedTypeIdentifier(for: provider) else {
            throw ExternalLearningMaterialImportError
                .unsupportedFile(provider.suggestedName ?? ExternalImportL10n.text("学习资料"))
        }

        if typeIdentifier == UTType.fileURL.identifier {
            return try await stageFileURLProvider(provider, store: store, batchID: batchID)
        }

        do {
            return try await stageFileRepresentation(
                provider, typeIdentifier: typeIdentifier, store: store, batchID: batchID
            )
        } catch {
            guard ExternalLearningMaterialImport.allowsDataRepresentationFallback(after: error) else { throw error }
        }

        return try await stageDataRepresentation(
            provider,
            typeIdentifier: typeIdentifier,
            store: store,
            batchID: batchID
        )
    }

    private func stageFileRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            ExternalLearningMaterialImportItem,
            Error
        >) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: NSError(domain: NSItemProvider.errorDomain, code: -1000))
                    return
                }

                do {
                    let item = try store.stageFile(
                        from: url,
                        batchID: batchID,
                        sourceContentTypeIdentifier: typeIdentifier,
                        originalFilename: Self.filename(
                            suggestedName: suggestedName,
                            typeIdentifier: typeIdentifier,
                            fileURL: url
                        )
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stageDataRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            ExternalLearningMaterialImportItem,
            Error
        >) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: ExternalLearningMaterialImportError.emptyBatch)
                    return
                }

                guard UTType(typeIdentifier)?.conforms(to: .image) == true else {
                    continuation
                        .resume(throwing: ExternalLearningMaterialImportError
                            .unsupportedFile(suggestedName ?? ExternalImportL10n.text("学习资料")))
                    return
                }

                do {
                    let item = try store.stageData(
                        data,
                        batchID: batchID,
                        originalFilename: Self.filename(suggestedName: suggestedName, typeIdentifier: typeIdentifier),
                        contentTypeIdentifier: typeIdentifier
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stageFileURLProvider(
        _ provider: NSItemProvider,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            ExternalLearningMaterialImportItem,
            Error
        >) in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard let url else {
                    continuation.resume(throwing: ExternalLearningMaterialImportError.emptyBatch)
                    return
                }

                do {
                    let item = try store.stageFile(from: url, batchID: batchID)
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func supportedTypeIdentifier(for provider: NSItemProvider) -> String? {
        for identifier in ExternalLearningMaterialImport.supportedContentTypeIdentifiers
            where provider.hasItemConformingToTypeIdentifier(identifier) {
            return identifier
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            ExternalLearningMaterialImport.isSupported(
                filename: provider.suggestedName ?? "",
                contentTypeIdentifier: identifier
            )
        }
    }

    private static func filename(
        suggestedName: String?,
        typeIdentifier: String,
        fileURL: URL? = nil
    ) -> String {
        let candidate = fileURL?.lastPathComponent ?? suggestedName ?? ExternalImportL10n.text("学习资料")
        let normalized = ExternalLearningMaterialImport.normalizedFilename(candidate)
        guard (normalized as NSString).pathExtension.isEmpty,
              let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension
        else {
            return normalized
        }
        return "\(normalized).\(fileExtension)"
    }

    @MainActor
    private func openContainingApp(batchID: UUID) async {
        statusLabel.text = ExternalImportL10n.text("已暂存，正在打开 MyLeafy...")
        let callbackURL = ExternalLearningMaterialImport.callbackURL(for: batchID)
        let success = await extensionContext?.open(callbackURL) ?? false
        if success {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            showManualOpenMessage(ExternalImportL10n.text("文件已暂存，请手动打开 MyLeafy 完成保存。"))
        }
    }

    @MainActor
    private func showManualOpenMessage(_ message: String) {
        statusLabel.text = message
        doneButton.isHidden = false
    }

    @objc
    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
