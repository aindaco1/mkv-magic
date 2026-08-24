#!/usr/bin/env swift

import Foundation

private struct CoverageMetric {
    var count = 0
    var covered = 0

    var percent: Double {
        guard count > 0 else { return 0 }
        return 100 * Double(covered) / Double(count)
    }
}

private struct CoverageMinimum {
    let key: String
    let label: String
    let percent: Double
}

private enum CoverageGateError: Error, CustomStringConvertible {
    case usage
    case invalidReport(String)
    case noSourceFiles(String)
    case belowMinimum(label: String, actual: Double, minimum: Double)

    var description: String {
        switch self {
        case .usage:
            return "usage: check-coverage.swift REPORT_JSON SOURCE_ROOT"
        case .invalidReport(let reason):
            return "invalid Swift coverage report: \(reason)"
        case .noSourceFiles(let root):
            return "coverage report contains no repository source files under \(root)"
        case .belowMinimum(let label, let actual, let minimum):
            return String(
                format: "%@ coverage %.2f%% is below the %.2f%% repository floor",
                label,
                actual,
                minimum
            )
        }
    }
}

private let minimums = [
    CoverageMinimum(key: "lines", label: "line", percent: 65),
    CoverageMinimum(key: "functions", label: "function", percent: 68),
    CoverageMinimum(key: "regions", label: "region", percent: 58),
]

private func coverageMetrics(reportURL: URL, sourceRootURL: URL) throws
    -> [String: CoverageMetric]
{
    let data = try Data(contentsOf: reportURL, options: [.mappedIfSafe])
    guard
        let report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let reportData = report["data"] as? [[String: Any]],
        let firstData = reportData.first,
        let files = firstData["files"] as? [[String: Any]]
    else {
        throw CoverageGateError.invalidReport("missing data[0].files")
    }

    let sourcePrefix = sourceRootURL.standardizedFileURL.path + "/"
    var sourceFileCount = 0
    var totals = Dictionary(
        uniqueKeysWithValues: minimums.map { ($0.key, CoverageMetric()) }
    )
    for file in files {
        guard
            let filename = file["filename"] as? String,
            URL(fileURLWithPath: filename).standardizedFileURL.path.hasPrefix(sourcePrefix)
        else { continue }
        guard let summary = file["summary"] as? [String: Any] else {
            throw CoverageGateError.invalidReport("missing summary for repository source")
        }
        sourceFileCount += 1
        for minimum in minimums {
            guard
                let metric = summary[minimum.key] as? [String: Any],
                let count = metric["count"] as? Int,
                let covered = metric["covered"] as? Int,
                count >= 0,
                covered >= 0,
                covered <= count
            else {
                throw CoverageGateError.invalidReport(
                    "invalid \(minimum.key) metric for repository source"
                )
            }
            totals[minimum.key]?.count += count
            totals[minimum.key]?.covered += covered
        }
    }
    guard sourceFileCount > 0 else {
        throw CoverageGateError.noSourceFiles(sourceRootURL.path)
    }
    return totals
}

private func run() throws {
    guard CommandLine.arguments.count == 3 else { throw CoverageGateError.usage }
    let reportURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let sourceRootURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    let totals = try coverageMetrics(reportURL: reportURL, sourceRootURL: sourceRootURL)

    for minimum in minimums {
        guard let total = totals[minimum.key] else {
            throw CoverageGateError.invalidReport("missing \(minimum.key) total")
        }
        print(
            String(
                format: "repository source %@ coverage: %.2f%% (%d/%d)",
                minimum.label,
                total.percent,
                total.covered,
                total.count
            )
        )
        guard total.percent >= minimum.percent else {
            throw CoverageGateError.belowMinimum(
                label: minimum.label,
                actual: total.percent,
                minimum: minimum.percent
            )
        }
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("coverage gate failed: \(error)\n".utf8))
    exit(1)
}
