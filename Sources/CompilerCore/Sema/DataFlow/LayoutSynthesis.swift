import Foundation

extension DataFlowSemaPhase {
    func synthesizeNominalLayouts(symbols: SymbolTable) {
        let nominalKinds: [SymbolKind] = [.class, .interface, .object, .enumClass, .annotationClass]
        let nominalIDs = nominalKinds.flatMap { symbols.symbols(ofKind: $0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !nominalIDs.isEmpty else { return }
        let topoOrder = buildTopoOrder(nominalIDs: nominalIDs, symbols: symbols)
        for nominalID in topoOrder {
            synthesizeLayoutForNominal(nominalID, symbols: symbols)
        }
    }

    private func buildTopoOrder(nominalIDs: [SymbolID], symbols: SymbolTable) -> [SymbolID] {
        var topoOrder: [SymbolID] = []
        var visited: Set<SymbolID> = []

        func visit(_ symbolID: SymbolID) {
            guard visited.insert(symbolID).inserted else { return }
            let superNominals = symbols.directSupertypes(for: symbolID)
                .filter { superID in
                    guard let superSymbol = symbols.symbol(superID) else { return false }
                    return isNominalLayoutTargetSymbol(superSymbol.kind)
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
            for superNominal in superNominals {
                visit(superNominal)
            }
            topoOrder.append(symbolID)
        }

        for nominalID in nominalIDs {
            visit(nominalID)
        }
        return topoOrder
    }

    private func synthesizeLayoutForNominal(_ nominalID: SymbolID, symbols: SymbolTable) {
        guard let nominalSymbol = symbols.symbol(nominalID) else { return }
        if nominalSymbol.flags.contains(.synthetic),
           symbols.nominalLayout(for: nominalID) != nil
        {
            return
        }

        let directSuperNominals = symbols.directSupertypes(for: nominalID)
            .compactMap { symbols.symbol($0) }
            .filter { isNominalLayoutTargetSymbol($0.kind) }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })

        let superClass = directSuperNominals.first(where: { $0.kind != .interface })?.id
        let layoutHint = symbols.nominalLayoutHint(for: nominalID)

        let inheritedVtable = superClass.flatMap { symbols.nominalLayout(for: $0)?.vtableSlots } ?? [:]
        let inheritedVtableSize = superClass.flatMap { symbols.nominalLayout(for: $0)?.vtableSize } ?? 0
        var vtableSlots = inheritedVtable
        var vtableSlotByKey: [MethodDispatchKey: Int] = [:]
        for methodID in inheritedVtable.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let methodSymbol = symbols.symbol(methodID),
                  let slot = inheritedVtable[methodID]
            else { continue }
            vtableSlotByKey[methodDispatchKey(for: methodSymbol, symbols: symbols)] = slot
        }

        var nextVtableSlot = max(inheritedVtableSize, (vtableSlots.values.max() ?? -1) + 1)
        let ownMethods = symbols.children(ofFQName: nominalSymbol.fqName)
            .filter { id in symbols.symbol(id)?.kind == .function }
            .sorted(by: { $0.rawValue < $1.rawValue })
            .compactMap { symbols.symbol($0) }
        for method in ownMethods {
            let key = methodDispatchKey(for: method, symbols: symbols)
            if let inheritedSlot = vtableSlotByKey[key] {
                vtableSlots[method.id] = inheritedSlot
                continue
            }
            vtableSlots[method.id] = nextVtableSlot
            vtableSlotByKey[key] = nextVtableSlot
            nextVtableSlot += 1
        }
        let vtableSize = max(nextVtableSlot, layoutHint?.declaredVtableSize ?? 0)

        let inheritedItable = superClass.flatMap { symbols.nominalLayout(for: $0)?.itableSlots } ?? [:]
        let inheritedItableSize = superClass.flatMap { symbols.nominalLayout(for: $0)?.itableSize } ?? 0
        var itableSlots = inheritedItable
        var nextItableSlot = max(inheritedItableSize, (itableSlots.values.max() ?? -1) + 1)
        for interfaceID in collectInterfaceSupertypes(of: nominalID, symbols: symbols) where itableSlots[interfaceID] == nil {
            itableSlots[interfaceID] = nextItableSlot
            nextItableSlot += 1
        }
        let itableSize = max(nextItableSlot, layoutHint?.declaredItableSize ?? 0)

        let ownFields: [SemanticSymbol] = if nominalSymbol.kind == .interface {
            // Interfaces have no backing field storage; skip property fields.
            []
        } else {
            symbols.children(ofFQName: nominalSymbol.fqName)
                .filter { id in
                    guard let kind = symbols.symbol(id)?.kind else { return false }
                    return kind == .field || kind == .property
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
                .compactMap { symbols.symbol($0) }
        }
        let ownFieldCount = ownFields.count
        let inheritedFieldCount = superClass.flatMap { symbols.nominalLayout(for: $0)?.instanceFieldCount } ?? 0
        // Keep nominal layout in sync with Runtime.KKObjHeader (typeInfo + flags/size).
        let objectHeaderWords = 2
        let inheritedFieldOffsets = superClass.flatMap { symbols.nominalLayout(for: $0)?.fieldOffsets } ?? [:]
        var fieldOffsets = inheritedFieldOffsets
        var nextFieldOffset = (inheritedFieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        for field in ownFields where fieldOffsets[field.id] == nil {
            fieldOffsets[field.id] = nextFieldOffset
            nextFieldOffset += 1
        }
        let instanceFieldCount = max(inheritedFieldCount + ownFieldCount, layoutHint?.declaredFieldCount ?? 0)
        let inheritedInstanceSizeWords = superClass.flatMap { symbols.nominalLayout(for: $0)?.instanceSizeWords } ?? 0
        let instanceSizeWords = max(
            max(objectHeaderWords + instanceFieldCount, inheritedInstanceSizeWords),
            layoutHint?.declaredInstanceSizeWords ?? 0
        )
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: instanceFieldCount,
                instanceSizeWords: instanceSizeWords,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots,
                vtableSize: vtableSize,
                itableSize: itableSize,
                superClass: superClass
            ),
            for: nominalID
        )
    }

    func isNominalLayoutTargetSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass:
            true
        default:
            false
        }
    }

    private func isDirectMemberSymbol(_ member: SemanticSymbol, of owner: SemanticSymbol) -> Bool {
        guard member.fqName.count == owner.fqName.count + 1 else {
            return false
        }
        return zip(owner.fqName, member.fqName).allSatisfy { $0 == $1 }
    }

    private func collectInterfaceSupertypes(of symbol: SymbolID, symbols: SymbolTable) -> [SymbolID] {
        var stack: [SymbolID] = symbols.directSupertypes(for: symbol)
        var visited: Set<SymbolID> = []
        var interfaces: [SymbolID] = []

        while let current = stack.popLast() {
            guard visited.insert(current).inserted else {
                continue
            }
            guard let currentSymbol = symbols.symbol(current) else {
                continue
            }

            if currentSymbol.kind == .interface {
                interfaces.append(current)
            }
            let next = symbols.directSupertypes(for: current)
                .sorted(by: { $0.rawValue < $1.rawValue })
            for candidate in next {
                stack.append(candidate)
            }
        }

        return interfaces.sorted(by: { $0.rawValue < $1.rawValue })
    }

    private struct MethodDispatchKey: Hashable {
        let name: InternedString
        let arity: Int
        let isSuspend: Bool
    }

    private func methodDispatchKey(for method: SemanticSymbol, symbols: SymbolTable) -> MethodDispatchKey {
        let signature = symbols.functionSignature(for: method.id)
        return MethodDispatchKey(
            name: method.name,
            arity: signature?.parameterTypes.count ?? 0,
            isSuspend: signature?.isSuspend ?? false
        )
    }
}
