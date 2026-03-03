import Foundation

struct VisibilityChecker {
    let symbols: SymbolTable

    func isAccessible(
        _ symbol: SemanticSymbol,
        fromFile accessFileID: FileID,
        enclosingClass: SymbolID?
    ) -> Bool {
        switch symbol.visibility {
        case .public, .internal:
            return true
        case .private:
            if isLocalOrParameter(symbol.kind) {
                return true
            }
            if let parent = symbols.parentSymbol(for: symbol.id) {
                return enclosingClass == parent || isEnclosedBy(enclosingClass, ancestor: parent)
            }
            guard let declSite = symbol.declSite else {
                return true
            }
            return declSite.start.file == accessFileID
        case .protected:
            guard let ownerClass = symbols.parentSymbol(for: symbol.id) else {
                return false
            }
            guard let enclosingClass else {
                return false
            }
            if enclosingClass == ownerClass {
                return true
            }
            return isSubclass(enclosingClass, of: ownerClass)
        }
    }

    private func isLocalOrParameter(_ kind: SymbolKind) -> Bool {
        kind == .local || kind == .valueParameter || kind == .label || kind == .typeParameter
    }

    private func isSubclass(_ candidate: SymbolID, of ancestor: SymbolID) -> Bool {
        var visited: Set<Int32> = []
        var queue = symbols.directSupertypes(for: candidate)
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            if current == ancestor { return true }
            if visited.contains(current.rawValue) { continue }
            visited.insert(current.rawValue)
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }
        return false
    }

    private func isEnclosedBy(_ candidate: SymbolID?, ancestor: SymbolID) -> Bool {
        var current = candidate
        while let c = current {
            if c == ancestor { return true }
            current = symbols.parentSymbol(for: c)
        }
        return false
    }
}
