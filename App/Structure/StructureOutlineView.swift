import AppKit
import BOMCore
import SwiftUI

/// The document's structure as an outline: lazy (children are read on
/// expansion), keyboard-native, and in sync with the source pane.
struct StructureOutlineView: NSViewRepresentable {
    let model: DocumentModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeView() }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.update(serial: model.selectionSerial, textSize: model.textSize)
    }

    /// NSOutlineView needs objects as items; one box per node, created on demand.
    final class Item: NSObject {
        let id: NodeID
        init(_ id: NodeID) { self.id = id }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let model: DocumentModel
        private var outline: StructureNSOutlineView!
        private var items: [Int32: Item] = [:]
        private var childCache: [Int32: [NodeID]] = [:]
        private var appliedSerial = -1
        private var appliedTextSize: CGFloat = 0
        private var applyingSelection = false

        init(model: DocumentModel) { self.model = model }

        private var tree: JSONTree { model.tree! }

        func item(_ id: NodeID) -> Item {
            if let item = items[id.rawValue] { return item }
            let item = Item(id)
            items[id.rawValue] = item
            return item
        }

        private func children(_ id: NodeID) -> [NodeID] {
            if let c = childCache[id.rawValue] { return c }
            let c = tree.children(id)
            childCache[id.rawValue] = c
            return c
        }

        func makeView() -> NSScrollView {
            let outline = StructureNSOutlineView()
            outline.coordinator = self
            let column = NSTableColumn(identifier: .init("node"))
            column.isEditable = false
            outline.addTableColumn(column)
            outline.outlineTableColumn = column
            outline.headerView = nil
            outline.style = .inset
            outline.backgroundColor = .controlBackgroundColor
            outline.rowHeight = Self.rowHeight(model.textSize)
            outline.indentationPerLevel = 14
            outline.autoresizesOutlineColumn = false
            outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            outline.allowsMultipleSelection = false
            outline.setAccessibilityLabel("Structure")
            outline.dataSource = self
            outline.delegate = self
            outline.menu = CopyMenu.make(target: self)

            let scrollView = NSScrollView()
            scrollView.documentView = outline
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            self.outline = outline
            appliedTextSize = model.textSize
            if let root = tree.root { outline.expandItem(item(root)) }
            return scrollView
        }

        static func rowHeight(_ textSize: CGFloat) -> CGFloat { ceil(textSize * 1.85) }

        func update(serial: Int, textSize: CGFloat) {
            guard outline != nil else { return }
            if textSize != appliedTextSize {
                appliedTextSize = textSize
                outline.rowHeight = Self.rowHeight(textSize)
                outline.reloadData()
                applySelection()
            }
            if serial != appliedSerial {
                appliedSerial = serial
                if model.selectionOrigin != .structure { applySelectionWhenReady() }
            }
        }

        /// At launch the outline may not be in a window or sized yet.
        private func applySelectionWhenReady(attempts: Int = 20) {
            if outline.window != nil, (outline.enclosingScrollView?.contentView.bounds.height ?? 0) > 0 {
                applySelection()
            } else if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.applySelectionWhenReady(attempts: attempts - 1)
                }
            }
        }

        private func applySelection() {
            guard let id = model.selection else {
                outline.deselectAll(nil)
                return
            }
            for ancestor in tree.ancestors(id) { outline.expandItem(item(ancestor)) }
            let row = outline.row(forItem: item(id))
            guard row >= 0 else { return }
            applyingSelection = true
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            applyingSelection = false
            centre(row: row)
        }

        private func centre(row: Int) {
            guard let clip = outline.enclosingScrollView?.contentView else { return }
            let rect = outline.rect(ofRow: row)
            if !clip.documentVisibleRect.contains(rect) {
                var target = clip.bounds
                target.origin.y = rect.midY - clip.bounds.height / 2
                clip.scroll(to: clip.constrainBoundsRect(target).origin)
                outline.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }

        /// Number of nodes in the subtree of `id` (pre-order arena).
        func subtreeSize(_ id: NodeID) -> Int {
            var c: NodeID? = id
            while let n = c {
                if let next = nextSibling(n) { return Int(next.rawValue - id.rawValue) }
                c = tree.parent(n)
            }
            return tree.nodeCount - Int(id.rawValue)
        }

        private func nextSibling(_ n: NodeID) -> NodeID? {
            guard let p = tree.parent(n) else { return nil }
            let siblings = children(p)
            let i = tree.indexInParent(n)
            return i + 1 < siblings.count ? siblings[i + 1] : nil
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? Item else { return tree.root == nil ? 0 : 1 }
            return tree.childCount(item.id)
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? Item else { return self.item(tree.root!) }
            return self.item(children(item.id)[index])
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? Item else { return false }
            return tree.childCount(item.id) > 0
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            let cell = outlineView.makeView(withIdentifier: .init("cell"), owner: nil) as? NSTableCellView ?? makeCell()
            let row = RowText(tree: tree, id: item.id, size: model.textSize)
            cell.textField?.attributedStringValue = row.attributed
            cell.toolTip = row.toolTip
            cell.imageView?.image = row.badge
            cell.imageView?.isHidden = row.badge == nil
            cell.setAccessibilityLabel(row.accessibilityLabel)
            return cell
        }

        private func makeCell() -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = .init("cell")
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.maximumNumberOfLines = 1
            text.usesSingleLineMode = true
            text.cell?.truncatesLastVisibleLine = true
            text.translatesAutoresizingMaskIntoConstraints = false
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.addSubview(image)
            cell.textField = text
            cell.imageView = image
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 4),
                image.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                image.centerYAnchor.constraint(equalTo: text.centerYAnchor),
            ])
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            CentredRowView()
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !applyingSelection else { return }
            let row = outline.selectedRow
            guard row >= 0, let item = outline.item(atRow: row) as? Item else { return }
            if item.id != model.selection { model.select(item.id, origin: .structure) }
        }

        // MARK: Context menu

        @objc func copyPointer(_ sender: Any?) { model.copy(.pointer, node: clickedOrSelected()) }
        @objc func copyValue(_ sender: Any?) { model.copy(.value, node: clickedOrSelected()) }
        @objc func copySource(_ sender: Any?) { model.copy(.source, node: clickedOrSelected()) }

        private func clickedOrSelected() -> NodeID? {
            let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
            return (outline.item(atRow: row) as? Item)?.id
        }
    }
}

/// ⌘C copies the selected node's original source; ⌥-click expansion is capped
/// so a large document cannot expand millions of rows at once.
final class StructureNSOutlineView: NSOutlineView {
    weak var coordinator: StructureOutlineView.Coordinator?
    static let maxRecursiveExpansion = 2_000

    @objc func copy(_ sender: Any?) { coordinator?.copySource(sender) }


    override func expandItem(_ item: Any?, expandChildren: Bool) {
        if expandChildren, let item = item as? StructureOutlineView.Item, let coordinator,
           coordinator.subtreeSize(item.id) > Self.maxRecursiveExpansion {
            super.expandItem(item, expandChildren: false)
            return
        }
        super.expandItem(item, expandChildren: expandChildren)
    }
}

/// Keeps the disclosure triangle vertically centred in tall rows (presentation size).
final class CentredRowView: NSTableRowView {
    override func layout() {
        super.layout()
        for view in subviews where view.identifier == NSOutlineView.disclosureButtonIdentifier {
            view.frame.origin.y = ((bounds.height - view.frame.height) / 2).rounded()
        }
    }
}

enum CopyMenu {
    @MainActor
    static func make(target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("Copy JSON Pointer", #selector(StructureOutlineView.Coordinator.copyPointer(_:))),
                                ("Copy Value", #selector(StructureOutlineView.Coordinator.copyValue(_:))),
                                ("Copy Source", #selector(StructureOutlineView.Coordinator.copySource(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        return menu
    }
}

/// The text of one outline row: key or index, then a short preview.
struct RowText {
    let attributed: NSAttributedString
    let toolTip: String?
    let badge: NSImage?
    let accessibilityLabel: String

    static let hintKeys = ["name", "id", "bom-ref", "ref", "title", "key"]

    @MainActor
    init(tree: JSONTree, id: NodeID, size: CGFloat) {
        let font = NSFont.systemFont(ofSize: size)
        let mono = NSFont.monospacedSystemFont(ofSize: size * 0.95, weight: .regular)
        let label: String
        if let key = tree.key(id) {
            label = key
        } else if let parent = tree.parent(id) {
            label = tree.kind(parent) == .array ? "[\(tree.indexInParent(id))]" : ""
        } else {
            label = "root"
        }
        let s = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        let preview = Self.preview(tree, id)
        s.append(NSAttributedString(string: "  " + preview.text, attributes: [
            .font: preview.mono ? mono : font,
            .foregroundColor: preview.colour,
        ]))
        attributed = s

        var tip = tree.pointer(id).displayString
        var badge: NSImage?
        if tree.pointer(id).occurrence != nil {
            badge = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Duplicate key")?
                .withSymbolConfiguration(.init(paletteColors: [.systemYellow]))
        }
        if tree.kind(id) == .invalid {
            let r = tree.valueRange(id)
            if let d = tree.diagnostics.first(where: { $0.range.overlaps(r) || $0.range.lowerBound == r.lowerBound }) {
                tip += "\n" + d.message
            }
            badge = NSImage(systemSymbolName: "xmark.octagon.fill", accessibilityDescription: "Invalid value")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        }
        toolTip = tip
        self.badge = badge
        accessibilityLabel = "\(label), \(preview.text)"
    }

    @MainActor
    static func preview(_ tree: JSONTree, _ id: NodeID) -> (text: String, colour: NSColor, mono: Bool) {
        switch tree.kind(id) {
        case .object:
            let count = tree.childCount(id)
            var text = "{\(count)}"
            if let hint = hint(tree, id) { text += "  " + hint }
            return (text, .secondaryLabelColor, false)
        case .array:
            return ("[\(tree.childCount(id))]", .secondaryLabelColor, false)
        case .string:
            return ("\"" + truncate(tree.decodedValue(id)) + "\"", .systemGreen, true)
        case .number:
            return (tree.decodedValue(id), .systemOrange, true)
        case .bool, .null:
            return (tree.decodedValue(id), .systemPurple, true)
        case .invalid:
            return (truncate(tree.decodedValue(id)), .systemRed, true)
        }
    }

    /// A readable hint for an object, e.g. a component's name and version.
    @MainActor
    static func hint(_ tree: JSONTree, _ id: NodeID) -> String? {
        var found: [String: String] = [:]
        for child in tree.children(id).prefix(24) {
            guard tree.kind(child) == .string, let key = tree.key(child),
                  key == "version" || hintKeys.contains(key) else { continue }
            if found[key] == nil { found[key] = tree.decodedValue(child) }
        }
        guard let name = hintKeys.lazy.compactMap({ found[$0] }).first else { return nil }
        let version = found["version"]
        return truncate([name, version].compactMap { $0 }.joined(separator: " "), 60)
    }

    static func truncate(_ s: String, _ n: Int = 80) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: "⏎")
        return flat.count > n ? String(flat.prefix(n)) + "…" : flat
    }
}
