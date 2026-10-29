import AppFolderKit
import Foundation
import UniformTypeIdentifiers

enum SharedWebsiteInputError: Error, Sendable, Equatable {
    case missingURL
    case multipleURLs
    case loadingFailed
    case invalidURL
}

/// Read the URL representation only. Text bodies, suggested names, webpage
/// preprocessing results and preview representations are deliberately unused.
enum SharedWebsiteInput {
    @MainActor
    static func provider(in items: [Any]) throws -> NSItemProvider {
        let providers = items.compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
        guard !providers.isEmpty else { throw SharedWebsiteInputError.missingURL }
        guard providers.count == 1 else { throw SharedWebsiteInputError.multipleURLs }
        guard let provider = providers.first,
              provider.canLoadObject(ofClass: NSURL.self) else {
            throw SharedWebsiteInputError.loadingFailed
        }
        return provider
    }

    nonisolated static func validatedAddress(_ address: String?) throws -> String {
        guard let address, let url = WebsiteURL.validated(address) else {
            throw SharedWebsiteInputError.invalidURL
        }
        return url.absoluteString
    }
}
