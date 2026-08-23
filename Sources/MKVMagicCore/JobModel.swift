import Foundation

public enum MediaJobState: String, Codable, CaseIterable, Hashable, Sendable {
    case queued
    case inspecting
    case planned
    case ready
    case running
    case verifying
    case committing
    case succeeded
    case cancelled
    case failed

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .cancelled, .failed: true
        default: false
        }
    }
}

public struct MediaJobInput: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let bookmarkID: UUID?
    public let privacySafeFacts: MediaJobInputFacts?

    public init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkID: UUID? = nil,
        privacySafeFacts: MediaJobInputFacts? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkID = bookmarkID
        self.privacySafeFacts = privacySafeFacts
    }
}

public struct MediaJobEvent: Codable, Hashable, Sendable {
    public let state: MediaJobState
    public let timestamp: Date
    public let message: String?

    public init(state: MediaJobState, timestamp: Date, message: String? = nil) {
        self.state = state
        self.timestamp = timestamp
        self.message = message
    }
}

public enum MediaJobTransitionError: Error, Equatable, Sendable {
    case terminalState(MediaJobState)
    case invalidTransition(from: MediaJobState, to: MediaJobState)
    case timestampMovedBackward
}

public struct MediaJobRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date
    public let workflowID: UUID
    public let workflowName: String
    public let inputs: [MediaJobInput]
    public let outputDisplayName: String?
    public let privacySafePlan: MediaJobPlanFacts?
    public private(set) var events: [MediaJobEvent]

    public init(
        schemaVersion: Int = MediaJobRecord.currentSchemaVersion,
        id: UUID = UUID(),
        createdAt: Date,
        workflowID: UUID,
        workflowName: String,
        inputs: [MediaJobInput],
        outputDisplayName: String? = nil,
        privacySafePlan: MediaJobPlanFacts? = nil,
        events: [MediaJobEvent]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.inputs = inputs
        self.outputDisplayName = outputDisplayName
        self.privacySafePlan = privacySafePlan
        self.events = events ?? [MediaJobEvent(state: .queued, timestamp: createdAt)]
    }

    public var state: MediaJobState {
        events.last?.state ?? .queued
    }

    public var updatedAt: Date {
        events.last?.timestamp ?? createdAt
    }

    public mutating func transition(
        to nextState: MediaJobState,
        at timestamp: Date,
        message: String? = nil
    ) throws {
        let currentState = state
        guard !currentState.isTerminal else {
            throw MediaJobTransitionError.terminalState(currentState)
        }
        guard timestamp >= updatedAt else {
            throw MediaJobTransitionError.timestampMovedBackward
        }
        guard Self.allowedTransitions[currentState, default: []].contains(nextState) else {
            throw MediaJobTransitionError.invalidTransition(from: currentState, to: nextState)
        }
        events.append(MediaJobEvent(state: nextState, timestamp: timestamp, message: message))
    }

    private static let allowedTransitions: [MediaJobState: Set<MediaJobState>] = [
        .queued: [.inspecting, .cancelled],
        .inspecting: [.planned, .failed, .cancelled],
        .planned: [.ready, .failed, .cancelled],
        .ready: [.running, .cancelled],
        .running: [.verifying, .failed, .cancelled],
        .verifying: [.committing, .failed, .cancelled],
        .committing: [.succeeded, .failed],
    ]
}
