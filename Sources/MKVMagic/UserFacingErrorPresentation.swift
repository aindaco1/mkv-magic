import Foundation

enum UserFacingErrorPresentation {
    static let maximumDetailCharacters = 240

    static func message(
        failure: String,
        recovery: String,
        error: Error
    ) -> String {
        "\(failure) \(recovery) Details: \(boundedDetail(error.localizedDescription))"
    }

    static func shortReason(_ error: Error) -> String {
        boundedDetail(error.localizedDescription)
    }

    private static func boundedDetail(_ rawDetail: String) -> String {
        var result = ""
        result.reserveCapacity(maximumDetailCharacters)
        var pendingSpace = false
        var wasTruncated = false
        for character in rawDetail {
            if character.isWhitespace {
                if !result.isEmpty { pendingSpace = true }
                continue
            }
            if pendingSpace {
                if result.count >= maximumDetailCharacters - 1 {
                    wasTruncated = true
                    break
                }
                result.append(" ")
                pendingSpace = false
            }
            guard result.count < maximumDetailCharacters else {
                wasTruncated = true
                break
            }
            result.append(character)
        }
        guard !result.isEmpty else { return "No additional details were provided." }
        if wasTruncated {
            if result.count == maximumDetailCharacters { result.removeLast() }
            result.append("…")
        }
        return result
    }
}
