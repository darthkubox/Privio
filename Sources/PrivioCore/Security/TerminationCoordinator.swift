import Foundation

/// A quit request is cancelled at the AppKit boundary while authentication and
/// cleanup run in the normal event loop. Only the immediate, synchronous retry
/// may terminate. A cancelled attempt never leaves a reusable quit permission.
@MainActor
public final class TerminationCoordinator {
    public private(set) var isPreparing = false
    public private(set) var isTerminationAuthorized = false

    public init() {}

    @discardableResult
    public func request(authorize: @escaping @MainActor () async -> Bool,
                        prepare: @escaping @MainActor () async -> Bool,
                        terminate: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard !isPreparing else { return nil }
        isPreparing = true
        return Task { @MainActor in
            defer { isPreparing = false }
            guard await authorize(), !Task.isCancelled,
                  await prepare(), !Task.isCancelled else { return }
            isTerminationAuthorized = true
            defer { isTerminationAuthorized = false }
            terminate()
        }
    }
}
