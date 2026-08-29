public protocol BoundedExecutionStage: Sendable {
    static var totalUnitCount: Int { get }
    var completedUnitCount: Int { get }
}

public enum VerifiedOutputExecutionStage: Equatable, Sendable, BoundedExecutionStage {
    case verifying
    case committing

    public static let totalUnitCount = 3

    public var completedUnitCount: Int {
        switch self {
        case .verifying: 1
        case .committing: 2
        }
    }
}
