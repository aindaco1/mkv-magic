import AppKit
import XCTest

@testable import MKVMagic

@MainActor
final class OutputSavePanelTests: XCTestCase {
    func testExportConfirmationIdentifiesTheSavedFileAndFolder() {
        XCTAssertEqual(
            OutputSavePanel.exportMessage(
                for: URL(fileURLWithPath: "/exports/Reports/report.json")),
            "Exported report.json in Reports.")
    }

    private static func access(_ url: URL) -> OutputDirectorySecurityScope? {
        OutputDirectorySecurityScope(
            directoryURL: url, startAccessing: { _ in true }, stopAccessing: { _ in })
    }

    func testChosenFolderAppliesToEveryOutputKindWithoutSaveDialog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "output-sweep-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OutputDestinationPreferences(defaults: defaults)
        try preferences.chooseFolder(root)
        for filename in [
            "video.mkv", "subtitle.srt", "tags.xml", "chapters.xml", "report.json",
            "recipe.mkvmagicworkflow", "cover.jpg",
        ] {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            let destination = try XCTUnwrap(
                OutputSavePanel.choose(
                    panel, preferences: preferences,
                    acquire: { Self.access($0) },
                    presentSave: { _ in
                        XCTFail("Established setting must not ask again")
                        return nil
                    },
                    requestExportFolder: {
                        XCTFail("Chosen folder also applies to exports")
                        return nil
                    }))
            XCTAssertEqual(
                destination.url.deletingLastPathComponent().standardizedFileURL,
                root.standardizedFileURL)
            XCTAssertEqual(destination.url.lastPathComponent, filename)
            try Data("preserve".utf8).write(to: destination.url)
            let next = try XCTUnwrap(
                OutputSavePanel.choose(
                    panel, preferences: preferences, acquire: { Self.access($0) }))
            XCTAssertNotEqual(next.url, destination.url)
            XCTAssertEqual(try Data(contentsOf: destination.url), Data("preserve".utf8))
        }
    }

    func testSourceLessExportsRememberFolderAcrossControllersAndAskModeIsExplicit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "output-export-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "report.json"
        var folderPrompts = 0
        for _ in 0..<2 {
            let destination = try OutputSavePanel.choose(
                panel,
                preferences: OutputDestinationPreferences(defaults: defaults),
                acquire: { Self.access($0) },
                presentSave: { _ in
                    XCTFail("Default export needs only a remembered folder")
                    return nil
                },
                requestExportFolder: {
                    folderPrompts += 1
                    return root
                })
            XCTAssertNotNil(destination)
        }
        XCTAssertEqual(folderPrompts, 1)
        let preferences = OutputDestinationPreferences(defaults: defaults)
        preferences.mode = .askEveryTime
        var savePrompts = 0
        let cancelled = try OutputSavePanel.choose(
            panel, preferences: preferences, acquire: { Self.access($0) },
            presentSave: { _ in
                savePrompts += 1
                return nil
            })
        XCTAssertNil(cancelled)
        XCTAssertEqual(savePrompts, 1)
        XCTAssertEqual(preferences.mode, .askEveryTime)
    }
}
