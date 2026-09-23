import Foundation

/// Retains the original capability-carrying URL for the full review/admission lifetime.
public final class SecurityScopedResourceAccess: @unchecked Sendable {
    public let url: URL
    private let stopAccessing: @Sendable () -> Void

    public init?(
        url: URL,
        startAccessing: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessing: @escaping @Sendable (URL) -> Void = {
            $0.stopAccessingSecurityScopedResource()
        }
    ) {
        guard startAccessing(url) else { return nil }
        self.url = url
        self.stopAccessing = { stopAccessing(url) }
    }

    deinit { stopAccessing() }
}
