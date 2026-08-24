import AppKit
import MKVMagicCore

@MainActor
final class JoinTrackMappingWindowController: NSWindowController {
    private let mappingViewController: JoinTrackMappingViewController
    private var completion: ((JoinTrackMapping?) -> Void)?

    init(sources: [MediaAsset], mapping: JoinTrackMapping, requiresResolution: Bool) {
        mappingViewController = JoinTrackMappingViewController(
            sources: sources,
            mapping: mapping,
            requiresResolution: requiresResolution
        )
        let window = NSPanel(contentViewController: mappingViewController)
        window.title = requiresResolution ? "Resolve Track Mapping" : "Edit Track Mapping"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 520))
        window.minSize = NSSize(width: 700, height: 420)
        super.init(window: window)
        mappingViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        mappingViewController.onUseMapping = { [weak self] mapping in
            self?.finish(with: mapping)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (JoinTrackMapping?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            self.completion = nil
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with mapping: JoinTrackMapping?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(mapping)
        completion = nil
    }
}

@MainActor
private final class JoinTrackMappingPopUpButton: NSPopUpButton {
    var sourceIndex = 0
    var laneIndex = 0
}

@MainActor
final class JoinTrackMappingViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onCancel: (() -> Void)?
    var onUseMapping: ((JoinTrackMapping) -> Void)?

    private let sources: [MediaAsset]
    private let initialMapping: JoinTrackMapping
    private let requiresResolution: Bool
    private var mapping: JoinTrackMapping
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let resetButton = NSButton(title: "Reset Proposal", target: nil, action: nil)
    private let useButton = NSButton(title: "Use This Mapping", target: nil, action: nil)

    init(sources: [MediaAsset], mapping: JoinTrackMapping, requiresResolution: Bool) {
        self.sources = sources
        initialMapping = mapping
        self.mapping = mapping
        self.requiresResolution = requiresResolution
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(
            labelWithString: requiresResolution
                ? "Resolve uncertain track lanes" : "Edit track lanes"
        )
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Each row becomes one output track. Choose which same-type track continues that lane in every Part. Selecting a track already used in another row swaps the two cells, so no source track is duplicated or discarded."
        )
        help.textColor = .secondaryLabelColor

        let laneColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lane"))
        laneColumn.title = "Output lane"
        laneColumn.width = 135
        laneColumn.minWidth = 120
        tableView.addTableColumn(laneColumn)
        for (sourceIndex, source) in sources.enumerated() {
            let column = NSTableColumn(
                identifier: NSUserInterfaceItemIdentifier("source-\(sourceIndex)")
            )
            column.title = "Part \(sourceIndex + 1) · \(source.sourceURL.lastPathComponent)"
            column.width = 250
            column.minWidth = 190
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 34
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        let tableScroll = NSScrollView()
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .bezelBorder

        let note = NSTextField(
            wrappingLabelWithString:
                "A “No track” cell is an explicit gap, not a deletion. Gaps and incompatible choices remain visible in the compatibility review and may require normalization."
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        resetButton.target = self
        resetButton.action = #selector(resetMapping)
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        useButton.target = self
        useButton.action = #selector(useMapping)
        useButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.maximumNumberOfLines = 2
        let actions = NSStackView(views: [
            statusLabel, spacer, resetButton, cancelButton, useButton,
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        let stack = NSStackView(views: [heading, help, tableScroll, note, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            tableScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        refreshStatus()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { mapping.lanes.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, mapping.lanes.indices.contains(row) else { return nil }
        if tableColumn.identifier.rawValue == "lane" {
            return laneCell(row: row)
        }
        guard tableColumn.identifier.rawValue.hasPrefix("source-"),
            let sourceIndex = Int(tableColumn.identifier.rawValue.dropFirst("source-".count)),
            sources.indices.contains(sourceIndex)
        else { return nil }
        return trackPopUp(sourceIndex: sourceIndex, laneIndex: row)
    }

    private func laneCell(row: Int) -> NSView {
        let lane = mapping.lanes[row]
        let ordinal = mapping.lanes.prefix(row + 1).filter { $0.kind == lane.kind }.count
        let label = NSTextField(labelWithString: "\(lane.kind.rawValue.capitalized) \(ordinal)")
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let cell = NSTableCellView()
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func trackPopUp(sourceIndex: Int, laneIndex: Int) -> NSPopUpButton {
        let lane = mapping.lanes[laneIndex]
        let currentTrackID = lane.trackIDsBySource[sourceIndex]
        let popup = JoinTrackMappingPopUpButton(frame: .zero, pullsDown: false)
        popup.sourceIndex = sourceIndex
        popup.laneIndex = laneIndex
        popup.target = self
        popup.action = #selector(selectTrack)
        if currentTrackID == nil {
            popup.addItem(withTitle: "No track in this Part")
            popup.lastItem?.representedObject = nil
        }
        let tracks = sources[sourceIndex].tracks.filter { $0.kind == lane.kind }
        for track in tracks {
            let assignedLane = mapping.lanes.firstIndex {
                $0.trackIDsBySource[sourceIndex] == track.id
            }
            var title = trackSummary(track)
            if let assignedLane, assignedLane != laneIndex {
                title += "  ·  Lane \(assignedLane + 1)"
            }
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = NSNumber(value: track.id)
        }
        if let currentTrackID,
            let item = popup.itemArray.first(where: {
                ($0.representedObject as? NSNumber)?.intValue == currentTrackID
            })
        {
            popup.select(item)
        } else {
            popup.selectItem(at: 0)
        }
        popup.toolTip = currentTrackID.map { "Source track #\($0)" } ?? "Explicit gap"
        return popup
    }

    private func trackSummary(_ track: MediaTrack) -> String {
        var facts = ["#\(track.id)", track.codec.uppercased()]
        if let language = track.language, !language.isEmpty { facts.append(language) }
        if let title = track.title, !title.isEmpty { facts.append(title) }
        switch track.kind {
        case .video:
            if let dimensions = track.dimensions {
                facts.append("\(dimensions.width)×\(dimensions.height)")
            }
        case .audio:
            if let layout = track.channelLayout, !layout.isEmpty {
                facts.append(layout)
            } else if let channels = track.channels {
                facts.append("\(channels) ch")
            }
        case .subtitle, .data, .attachment, .unknown:
            break
        }
        if track.isForced { facts.append("forced") }
        if track.isCommentary { facts.append("commentary") }
        if track.isHearingImpaired { facts.append("hearing impaired") }
        if track.isDefault { facts.append("default") }
        return facts.joined(separator: " · ")
    }

    @objc private func selectTrack(_ sender: JoinTrackMappingPopUpButton) {
        guard let trackID = (sender.selectedItem?.representedObject as? NSNumber)?.intValue else {
            return
        }
        do {
            mapping = try JoinTrackMappingEditor().assigning(
                trackID: trackID,
                fromSource: sender.sourceIndex,
                toLane: sender.laneIndex,
                sources: sources,
                mapping: mapping
            )
            tableView.reloadData()
            refreshStatus()
        } catch {
            statusLabel.stringValue = UserFacingErrorPresentation.message(
                failure: "Could not update the track mapping.",
                recovery: "The last valid mapping remains shown; choose a different track.",
                error: error
            )
            statusLabel.textColor = .systemRed
            tableView.reloadData()
        }
    }

    @objc private func resetMapping() {
        mapping = initialMapping
        tableView.reloadData()
        refreshStatus()
    }

    @objc private func cancel() { onCancel?() }

    @objc private func useMapping() {
        do {
            _ = try JoinCompatibilityAnalyzer().analyze(sources: sources, mapping: mapping)
            onUseMapping?(mapping)
        } catch {
            statusLabel.stringValue = UserFacingErrorPresentation.message(
                failure: "Could not use this track mapping.",
                recovery: "No join was started; complete every required lane and try again.",
                error: error
            )
            statusLabel.textColor = .systemRed
        }
    }

    private func refreshStatus() {
        let gapCount = mapping.lanes.reduce(0) { partial, lane in
            partial + lane.trackIDsBySource.filter { $0 == nil }.count
        }
        let gapSummary = gapCount == 1 ? "1 explicit gap" : "\(gapCount) explicit gaps"
        statusLabel.stringValue =
            "\(mapping.lanes.count) output lanes · \(gapSummary) · every source track assigned once"
        statusLabel.textColor = requiresResolution ? .systemOrange : .secondaryLabelColor
        resetButton.isEnabled = mapping != initialMapping
        useButton.isEnabled = true
    }
}
