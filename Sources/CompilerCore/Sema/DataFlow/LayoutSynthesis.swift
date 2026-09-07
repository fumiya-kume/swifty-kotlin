
extension DataFlowSemaPhase {
    func synthesizeNominalLayouts(symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
        let nominalKinds: [SymbolKind] = [.class, .interface, .object, .enumClass, .annotationClass]
        let nominalIDs = nominalKinds.flatMap { symbols.symbols(ofKind: $0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !nominalIDs.isEmpty else { return }
        let topoOrder = buildTopoOrder(nominalIDs: nominalIDs, symbols: symbols)
        for nominalID in topoOrder {
            synthesizeLayoutForNominal(nominalID, symbols: symbols, types: types, interner: interner)
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

    private func synthesizeLayoutForNominal(_ nominalID: SymbolID, symbols: SymbolTable, types: TypeSystem, interner: StringInterner) {
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
        // Bucketed by the coarse (name, arity, isSuspend) key: two sibling overloads
        // that merely share arity (e.g. `nextBytes(array: ByteArray)` and
        // `nextBytes(size: Int)`) must not be conflated into one vtable slot, so each
        // key can hold multiple candidates disambiguated by parameter types below.
        // Built once from genuine inheritance and never mutated afterwards, so that:
        // (1) a multi-level generic override chain doesn't see spurious "multiple
        // candidates" just because each ancestor level stored its own distinct
        // type-parameter symbols for what is really the same slot — deduped by slot
        // number below; (2) a same-class non-override sibling can never leak into
        // the candidate set that a later override in this same class consults.
        let inheritedCandidatesByKey = vtableInheritedCandidatesByKey(
            inheritedVtableSlots: inheritedVtable, symbols: symbols
        )

        var nextVtableSlot = max(inheritedVtableSize, (vtableSlots.values.max() ?? -1) + 1)
        let ownMethods = Self.orderedOwnMethods(
            for: nominalSymbol,
            symbols: symbols,
            interner: interner
        )
        for method in ownMethods {
            let key = vtableMethodDispatchKey(for: method, symbols: symbols)
            let candidates = inheritedCandidatesByKey[key]
            let parameterTypes = symbols.functionSignature(for: method.id)?.parameterTypes ?? []
            // Only a genuine `override` may reuse an inherited slot: a
            // freshly-declared (non-override) method can share (name, arity) with
            // an unrelated inherited overload without ever being in an override
            // relationship with it (Kotlin disallows two identical-signature
            // siblings, so any same-key sibling is necessarily a distinct overload
            // needing its own slot).
            if method.flags.contains(.overrideMember), let candidates {
                if let matchedSlot = resolveOverriddenVtableSlot(parameterTypes: parameterTypes, candidates: candidates, types: types) {
                    vtableSlots[method.id] = matchedSlot
                    continue
                }
            }
            if let candidates,
               let matchedSlot = resolveImplicitImportedOverrideSlot(
                   method: method,
                   owner: nominalSymbol,
                   declaredVtableSize: layoutHint?.declaredVtableSize,
                   nextVtableSlot: nextVtableSlot,
                   parameterTypes: parameterTypes,
                   candidates: candidates,
                   types: types
               )
            {
                vtableSlots[method.id] = matchedSlot
                continue
            }
            vtableSlots[method.id] = nextVtableSlot
            nextVtableSlot += 1
        }

        // BUG-227: give open/abstract/override properties a vtable slot for
        // their getter (and setter, for `var`) accessor, exactly like methods
        // above, so a property read/write through a base-typed reference
        // dispatches to the actual runtime type's implementation instead of
        // always reading the statically-resolved declaration's own storage.
        // Interfaces are excluded: they have no per-instance field storage of
        // their own and already dispatch stored/abstract properties through
        // the separate itable-relative slot space BUG-141 introduced
        // (kirInterfacePropertyGetterSlots) — this loop must not create a
        // second, inconsistent slot space for the same property there.
        let ownAccessorProperties = Self.orderedOwnAccessorProperties(
            for: nominalSymbol,
            symbols: symbols
        )
        for property in ownAccessorProperties {
            // Properties cannot be overloaded, so — unlike methods above,
            // which must disambiguate same-(name, arity) siblings — a name
            // match against the class's own inheritance chain is always
            // unambiguous.
            let inheritedProperty = property.flags.contains(.overrideMember)
                ? Self.findInheritedClassProperty(named: property.name, startingAt: nominalID, symbols: symbols)
                : nil

            let getterAccessor = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property.id)
            if let inheritedProperty,
               let matchedSlot = inheritedVtable[SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: inheritedProperty)]
            {
                vtableSlots[getterAccessor] = matchedSlot
            } else {
                vtableSlots[getterAccessor] = nextVtableSlot
                nextVtableSlot += 1
            }

            guard property.flags.contains(.mutable) else { continue }
            let setterAccessor = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: property.id)
            if let inheritedProperty,
               let matchedSlot = inheritedVtable[SyntheticSymbolScheme.propertySetterAccessorSymbol(for: inheritedProperty)]
            {
                vtableSlots[setterAccessor] = matchedSlot
            } else {
                vtableSlots[setterAccessor] = nextVtableSlot
                nextVtableSlot += 1
            }
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
                .compactMap { id -> SymbolID? in
                    guard let kind = symbols.symbol(id)?.kind else { return nil }
                    switch kind {
                    case .field:
                        return id
                    case .property:
                        // Properties with a dedicated backing field (custom
                        // getter/setter bodies referencing `field`, or Kotlin 2.0
                        // explicit backing fields) store their value in that
                        // symbol's slot, not the property symbol's own — the
                        // property itself has no storage in that case. This must
                        // match the `backingFieldSymbol(for:) ?? propertySymbol`
                        // lookup convention used throughout KIR lowering (reads,
                        // writes, lateinit checks, synthesized toString/equals).
                        guard !symbols.symbol(id)!.flags.contains(.abstractType) else {
                            return nil
                        }
                        // Getter-only computed properties have no instance
                        // storage. Their accessor is the complete
                        // implementation, so do not allocate a field that
                        // would be read as an uninitialized default value.
                        guard !symbols.propertyHasCustomGetter(for: id)
                            || symbols.backingFieldSymbol(for: id) != nil
                        else {
                            return nil
                        }
                        return symbols.backingFieldSymbol(for: id) ?? id
                    default:
                        return nil
                    }
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

    /// Legacy imported metadata can provide only the final vtable size without
    /// per-method slot entries or override flags. If allocating a fresh slot
    /// would exceed that imported size, preserve the metadata layout by reusing
    /// the one compatible inherited slot.
    private func resolveImplicitImportedOverrideSlot(
        method: SemanticSymbol,
        owner: SemanticSymbol,
        declaredVtableSize: Int?,
        nextVtableSlot: Int,
        parameterTypes: [TypeID],
        candidates: [(parameterTypes: [TypeID], slot: Int)],
        types: TypeSystem
    ) -> Int? {
        guard method.flags.contains(.importedLibrary),
              owner.flags.contains(.importedLibrary),
              let declaredVtableSize,
              nextVtableSlot + 1 > declaredVtableSize
        else {
            return nil
        }
        let compatibleSlots = Set(candidates.filter {
            isOverrideVtableParameterMatch(candidateParameterTypes: $0.parameterTypes, overrideParameterTypes: parameterTypes, types: types)
        }.map(\.slot))
        return compatibleSlots.count == 1 ? compatibleSlots.first : nil
    }

    /// Returns the direct function children of `nominalSymbol`, sorted stably by
    /// raw symbol ID. For `kotlin.sequences.Sequence` we force `iterator()` to be
    /// assigned vtable slot 0. The runtime helper that traverses source Sequence
    /// objects (`runtimeTraverseSourceSequenceObject`) dispatches `iterator()`
    /// through the Sequence itable using a fixed method slot; keeping that slot
    /// at 0 lets the compiler and runtime agree without passing per-interface
    /// method counts across the ABI.
    private static func orderedOwnMethods(
        for nominalSymbol: SemanticSymbol,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SemanticSymbol] {
        let methods = symbols.children(ofFQName: nominalSymbol.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .function }

        let isSequence = nominalSymbol.fqName.count == 3
            && interner.resolve(nominalSymbol.fqName[0]) == "kotlin"
            && interner.resolve(nominalSymbol.fqName[1]) == "sequences"
            && interner.resolve(nominalSymbol.name) == "Sequence"
        guard isSequence else {
            return methods.sorted(by: { $0.id.rawValue < $1.id.rawValue })
        }

        return methods.sorted { lhs, rhs in
            let lhsIsIterator = interner.resolve(lhs.name) == "iterator"
                && (symbols.functionSignature(for: lhs.id)?.parameterTypes.isEmpty ?? false)
            let rhsIsIterator = interner.resolve(rhs.name) == "iterator"
                && (symbols.functionSignature(for: rhs.id)?.parameterTypes.isEmpty ?? false)
            if lhsIsIterator != rhsIsIterator {
                return lhsIsIterator && !rhsIsIterator
            }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    /// This nominal's own properties that ever need virtual dispatch: the
    /// open/abstract root of an override chain, or a link further down it.
    /// A plain `final` property is never overridden in either direction, so
    /// it keeps the existing direct field-offset/accessor-call fast path
    /// untouched and never needs a slot here.
    private static func orderedOwnAccessorProperties(
        for nominalSymbol: SemanticSymbol,
        symbols: SymbolTable
    ) -> [SemanticSymbol] {
        guard nominalSymbol.kind != .interface else {
            return []
        }
        return symbols.children(ofFQName: nominalSymbol.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .property }
            .filter {
                $0.flags.contains(.openType)
                    || $0.flags.contains(.abstractType)
                    || $0.flags.contains(.overrideMember)
            }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
    }

    /// Walks `nominalID`'s superclass chain (never interfaces — those are
    /// BUG-141's separate itable-relative slot space) for the nearest
    /// ancestor that directly declares a property named `name`. Properties
    /// cannot be overloaded, so a name match is always the property being
    /// overridden — no arity/type disambiguation is needed the way method
    /// overrides require.
    private static func findInheritedClassProperty(
        named name: InternedString,
        startingAt nominalID: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        func superclass(of symbolID: SymbolID) -> SymbolID? {
            symbols.directSupertypes(for: symbolID).first { symbols.symbol($0)?.kind == .class }
        }

        var visited: Set<SymbolID> = []
        var current = superclass(of: nominalID)
        while let ancestorID = current, visited.insert(ancestorID).inserted {
            guard let ancestorSym = symbols.symbol(ancestorID) else { return nil }
            let match = symbols.children(ofFQName: ancestorSym.fqName).first { childID in
                guard let child = symbols.symbol(childID) else { return false }
                return child.kind == .property && child.name == name
            }
            if let match {
                return match
            }
            current = superclass(of: ancestorID)
        }
        return nil
    }
}
