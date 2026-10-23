import Foundation
import SwiftData

enum CampusStoreScope {
    static func configuration(
        schema: Schema,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) -> ModelConfiguration {
        guard let identity,
              let scopedURL = scopedStoreURL(for: identity) else {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }

        return ModelConfiguration(
            "Leafy-\(identity.scopeKey)",
            schema: schema,
            url: scopedURL,
            cloudKitDatabase: .none
        )
    }

    static func scopedStoreURL(for identity: CampusIdentity) -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupport
            .appendingPathComponent("CampusStores", isDirectory: true)
            .appendingPathComponent(identity.scopeKey, isDirectory: true)
            .appendingPathComponent("Leafy.store")
    }
}
