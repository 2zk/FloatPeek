import Foundation

struct FileSelection {
    enum Direction {
        case left
        case right
        case up
        case down
    }

    enum Mode {
        case replace
        case toggle
        case range
    }

    private(set) var focusedID: FileItem.ID?
    private(set) var selectedIDs: Set<FileItem.ID> = []
    private var anchorID: FileItem.ID?

    mutating func clear() {
        focusedID = nil
        selectedIDs = []
        anchorID = nil
    }

    mutating func select(
        _ id: FileItem.ID,
        mode: Mode,
        orderedIDs: [FileItem.ID]
    ) {
        switch mode {
        case .replace:
            replace(with: id)
        case .toggle:
            toggle(id, orderedIDs: orderedIDs)
        case .range:
            selectRange(to: id, orderedIDs: orderedIDs)
        }
    }

    @discardableResult
    mutating func move(
        _ direction: Direction,
        columnCount: Int,
        orderedIDs: [FileItem.ID],
        extendingSelection: Bool = false
    ) -> Bool {
        guard !orderedIDs.isEmpty else {
            return false
        }

        guard let focusedID,
              let currentIndex = orderedIDs.firstIndex(of: focusedID) else {
            replace(with: orderedIDs[0])
            return true
        }

        let normalizedColumnCount = max(columnCount, 1)
        let targetIndex: Int

        switch direction {
        case .left:
            targetIndex = currentIndex - 1
        case .right:
            targetIndex = currentIndex + 1
        case .up:
            targetIndex = currentIndex - normalizedColumnCount
        case .down:
            targetIndex = currentIndex + normalizedColumnCount
        }

        guard orderedIDs.indices.contains(targetIndex) else {
            return false
        }

        if extendingSelection {
            selectRange(to: orderedIDs[targetIndex], orderedIDs: orderedIDs)
        } else {
            replace(with: orderedIDs[targetIndex])
        }
        return true
    }

    mutating func reconcile(orderedIDs: [FileItem.ID]) {
        let validIDs = Set(orderedIDs)
        selectedIDs.formIntersection(validIDs)

        guard !selectedIDs.isEmpty else {
            clear()
            return
        }

        if focusedID.map({ selectedIDs.contains($0) }) != true {
            focusedID = orderedIDs.first(where: selectedIDs.contains)
        }

        if anchorID.map({ selectedIDs.contains($0) }) != true {
            anchorID = focusedID
        }
    }

    @discardableResult
    mutating func selectAll(orderedIDs: [FileItem.ID]) -> Bool {
        guard !orderedIDs.isEmpty else {
            return false
        }

        selectedIDs = Set(orderedIDs)
        if focusedID.map({ selectedIDs.contains($0) }) != true {
            focusedID = orderedIDs[0]
        }
        anchorID = focusedID
        return true
    }

    private mutating func replace(with id: FileItem.ID) {
        focusedID = id
        selectedIDs = [id]
        anchorID = id
    }

    private mutating func toggle(
        _ id: FileItem.ID,
        orderedIDs: [FileItem.ID]
    ) {
        if selectedIDs.remove(id) != nil {
            if focusedID == id {
                focusedID = orderedIDs.first(where: selectedIDs.contains)
            }
        } else {
            selectedIDs.insert(id)
            focusedID = id
        }

        anchorID = id
    }

    private mutating func selectRange(
        to id: FileItem.ID,
        orderedIDs: [FileItem.ID]
    ) {
        guard let anchorID,
              let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: id) else {
            replace(with: id)
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIDs = Set(orderedIDs[range])
        focusedID = id
    }
}
