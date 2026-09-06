func kirVtableImplementations(
    for nominalSymbol: SymbolID,
    sema: SemaModule
) -> [(slot: Int, implementation: SymbolID)] {
    guard let layout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return []
    }

    let virtualSlots = Set(layout.vtableSlots.compactMap { methodSymbol, slot -> Int? in
        guard let owner = sema.symbols.parentSymbol(for: methodSymbol),
              !sema.symbols.directSubtypes(of: owner).isEmpty,
              let symbol = sema.symbols.symbol(methodSymbol),
              symbol.kind == .function || symbol.kind == .property
        else {
            return nil
        }
        return slot
    })
    guard !virtualSlots.isEmpty else {
        return []
    }

    var bestBySlot: [Int: (distance: Int, implementation: SymbolID)] = [:]
    for (methodSymbol, slot) in layout.vtableSlots where virtualSlots.contains(slot) {
        guard let methodInfo = sema.symbols.symbol(methodSymbol),
              methodInfo.kind == .function || methodInfo.kind == .property,
              let owner = sema.symbols.parentSymbol(for: methodSymbol),
              let distance = kirNominalDistance(from: nominalSymbol, to: owner, sema: sema)
        else {
            continue
        }
        let implementation: SymbolID = if methodInfo.kind == .property {
            sema.symbols.extensionPropertyGetterAccessor(for: methodSymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: methodSymbol)
        } else {
            methodSymbol
        }
        if let current = bestBySlot[slot] {
            let isMoreSpecific = distance < current.distance
            let isStableTieBreak = distance == current.distance
                && implementation.rawValue > current.implementation.rawValue
            if isMoreSpecific || isStableTieBreak {
                bestBySlot[slot] = (distance, implementation)
            }
        } else {
            bestBySlot[slot] = (distance, implementation)
        }
    }

    return bestBySlot
        .map { (slot: $0.key, implementation: $0.value.implementation) }
        .sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return lhs.implementation.rawValue < rhs.implementation.rawValue
        }
}

func appendObjectVtableMethodRegistrations(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    let implementations = kirVtableImplementations(for: nominalSymbol, sema: sema)
    if !implementations.isEmpty {
        let intType = sema.types.intType
        let registerCallee = interner.intern("kk_object_register_vtable_method")
        for implementation in implementations {
            let slotExpr = arena.appendExpr(.intLiteral(Int64(implementation.slot)), type: intType)
            instructions.append(.constValue(result: slotExpr, value: .intLiteral(Int64(implementation.slot))))
            let methodFnExpr = arena.appendExpr(.symbolRef(implementation.implementation), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementation.implementation)))
            let registerResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [objectValue, slotExpr, methodFnExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    // BUG-227: also register property getter/setter accessor implementations
    // into the vtable, mirroring how BUG-141 registers interface property
    // getters alongside interface methods below.
    appendObjectVtablePropertyAccessorRegistrations(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
}

/// BUG-227: analog of `kirVtableImplementations` for property accessors.
/// Property-accessor keys in `layout.vtableSlots` are synthetic IDs (an
/// arithmetic transform of the underlying property's own symbol — see
/// `SyntheticSymbolScheme` — not real, symbol-table-registered entries), so
/// they cannot reuse `kirVtableImplementations`'s
/// `sema.symbols.symbol(methodSymbol)?.kind == .function` filter or its
/// `parentSymbol`-based ownership/distance lookup directly: both would treat
/// every property-accessor slot as "no owner found" and silently drop it.
/// This walks the same slot set, decoding each accessor entry back to its
/// original property to answer the identical question: for this concrete
/// class, which override in the chain is the closest (most specific)
/// implementation of the accessor occupying this slot?
func kirVtablePropertyAccessorImplementations(
    for nominalSymbol: SymbolID,
    sema: SemaModule
) -> [(slot: Int, implementation: SymbolID)] {
    guard let layout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return []
    }

    let virtualSlots = Set(layout.vtableSlots.compactMap { accessorSymbol, slot -> Int? in
        guard let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(accessorSymbol),
              let owner = sema.symbols.parentSymbol(for: decoded.property),
              !sema.symbols.directSubtypes(of: owner).isEmpty
        else {
            return nil
        }
        return slot
    })
    guard !virtualSlots.isEmpty else {
        return []
    }

    var bestBySlot: [Int: (distance: Int, implementation: SymbolID)] = [:]
    for (accessorSymbol, slot) in layout.vtableSlots where virtualSlots.contains(slot) {
        guard let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(accessorSymbol),
              let owner = sema.symbols.parentSymbol(for: decoded.property),
              let distance = kirNominalDistance(from: nominalSymbol, to: owner, sema: sema)
        else {
            continue
        }
        if let current = bestBySlot[slot] {
            let isMoreSpecific = distance < current.distance
            let isStableTieBreak = distance == current.distance
                && accessorSymbol.rawValue > current.implementation.rawValue
            if isMoreSpecific || isStableTieBreak {
                bestBySlot[slot] = (distance, accessorSymbol)
            }
        } else {
            bestBySlot[slot] = (distance, accessorSymbol)
        }
    }

    return bestBySlot
        .map { (slot: $0.key, implementation: $0.value.implementation) }
        .sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return lhs.implementation.rawValue < rhs.implementation.rawValue
        }
}

func appendObjectVtablePropertyAccessorRegistrations(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    let implementations = kirVtablePropertyAccessorImplementations(for: nominalSymbol, sema: sema)
    guard !implementations.isEmpty else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_vtable_method")
    for implementation in implementations {
        let slotExpr = arena.appendExpr(.intLiteral(Int64(implementation.slot)), type: intType)
        instructions.append(.constValue(result: slotExpr, value: .intLiteral(Int64(implementation.slot))))
        let accessorFnExpr = arena.appendExpr(.symbolRef(implementation.implementation), type: intType)
        instructions.append(.constValue(result: accessorFnExpr, value: .symbolRef(implementation.implementation)))
        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: registerCallee,
            arguments: [objectValue, slotExpr, accessorFnExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
    }
}

/// Returns a bridge symbol for `implementation` when its ABI (String aggregate
/// vs raw pointer) does not match the erased interface method signature used by
/// itable dispatch. The bridge has the interface ABI, forwards to the
/// implementation, and relies on the backend's String bridging in `.call` and
/// `returnValue` to convert across the boundary.
func itableBridgeSymbolForMethod(
    interfaceMethod: SymbolID,
    implementation: SymbolID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    arena: KIRArena,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID {
    guard implementation != interfaceMethod,
          implementation.rawValue >= 0,
          let implementationFn = arena.function(for: implementation),
          let interfaceSig = sema.symbols.functionSignature(for: interfaceMethod),
          let implSig = sema.symbols.functionSignature(for: implementation)
    else {
        return implementation
    }

    func isStringAggregate(_ type: TypeID?) -> Bool {
        guard let type else { return false }
        if case .stringStruct = sema.types.kind(of: type) {
            return true
        }
        return false
    }

    let interfaceReceiver = interfaceSig.receiverType
    let interfaceParamTypes = [interfaceReceiver].compactMap { $0 } + interfaceSig.parameterTypes
    let implementationParamTypes = implementationFn.params.map(\.type)

    guard implementationParamTypes.count == interfaceParamTypes.count else {
        return implementation
    }

    var needsBridge = false
    if isStringAggregate(implementationFn.returnType) != isStringAggregate(interfaceSig.returnType) {
        needsBridge = true
    }
    if !needsBridge {
        for (implType, ifaceType) in zip(implementationParamTypes, interfaceParamTypes) {
            if isStringAggregate(implType) != isStringAggregate(ifaceType) {
                needsBridge = true
                break
            }
        }
    }
    guard needsBridge else {
        return implementation
    }

    let cacheKey = "\(interfaceMethod.rawValue)|\(implementation.rawValue)"
    if let cached = driver.ctx.itableBridgeSymbolsByKey[cacheKey] {
        return cached
    }

    let bridgeSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
    driver.ctx.itableBridgeSymbolsByKey[cacheKey] = bridgeSymbol

    let bridgeName = interner.intern("kk_itable_bridge_\(interfaceMethod.rawValue)_\(implementation.rawValue)_\(bridgeSymbol.rawValue)")

    var bridgeParams: [KIRParameter] = []
    if let receiverType = interfaceSig.receiverType {
        let receiverSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        bridgeParams.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
    }
    for paramType in interfaceSig.parameterTypes {
        let paramSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        bridgeParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
    }

    var body: [KIRInstruction] = [.beginBlock]
    var bridgeParamExprs: [KIRExprID] = []
    for param in bridgeParams {
        let expr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
        body.append(.constValue(result: expr, value: .symbolRef(param.symbol)))
        bridgeParamExprs.append(expr)
    }

    let callResult = arena.appendTemporary(type: implementationFn.returnType)
    let thrownResult: KIRExprID? = implSig.canThrow
        ? arena.appendTemporary(type: sema.types.nullableAnyType)
        : nil

    let implName = interner.intern("__itable_impl_\(implementation.rawValue)")

    body.append(.call(
        symbol: implementation,
        callee: implName,
        arguments: bridgeParamExprs,
        result: callResult,
        canThrow: implSig.canThrow,
        thrownResult: thrownResult
    ))

    if let thrownResult {
        let continueLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
        body.append(.jump(continueLabel))
        body.append(.label(rethrowLabel))
        body.append(.rethrow(value: thrownResult))
        body.append(.label(continueLabel))
    }

    body.append(.returnValue(callResult))
    body.append(.endBlock)

    let bridgeDecl = arena.appendDecl(
        .function(
            KIRFunction(
                symbol: bridgeSymbol,
                name: bridgeName,
                params: bridgeParams,
                returnType: interfaceSig.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        )
    )
    driver.ctx.appendGeneratedCallableDecl(bridgeDecl)

    return bridgeSymbol
}

/// Registers every direct supertype edge in the ancestor graph of `childSymbol`.
/// Constructor sites used to emit only `child → direct parent`, so a never-
/// instantiated intermediate interface (`Ranked : Comparable<Ranked>`) never
/// contributed `Ranked → Comparable`. Erased `kk_compare_any` then could not
/// prove the operands were Comparable and fell back to pointer comparison.
func appendNominalSupertypeEdgeRegistrations(
    childSymbol: SymbolID,
    extraDirectSupertypes: [SymbolID] = [],
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    let intType = sema.types.intType
    var pending: [SymbolID] = [childSymbol]
    var visited: Set<SymbolID> = []

    while let current = pending.popLast() {
        guard visited.insert(current).inserted else { continue }
        var parents = sema.symbols.directSupertypes(for: current)
        if current == childSymbol {
            for extra in extraDirectSupertypes where !parents.contains(extra) {
                parents.append(extra)
            }
        }
        pending.append(contentsOf: parents)
        guard !parents.isEmpty else { continue }

        let currentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: current,
            sema: sema,
            interner: interner
        )
        guard currentTypeID != 0 else { continue }
        let currentExpr = arena.appendExpr(.intLiteral(currentTypeID), type: intType)
        instructions.append(.constValue(result: currentExpr, value: .intLiteral(currentTypeID)))

        var registeredParents: Set<SymbolID> = []
        for parent in parents {
            guard registeredParents.insert(parent).inserted else { continue }
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: parent,
                sema: sema,
                interner: interner
            )
            guard parentTypeID != 0 else { continue }
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let registerResult = arena.appendTemporary(type: intType)
            let superKind = sema.symbols.symbol(parent)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [currentExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
}

func appendObjectItableMethodRegistrations(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    guard let _ = sema.symbols.symbol(nominalSymbol),
          let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol)
    else {
        return
    }

    let intType = sema.types.intType
    let interfaceSupertypes = kirTransitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)
    for interfaceSymbol in interfaceSupertypes {
        guard let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else {
            continue
        }

        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))

        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))

        let registerIfaceResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_iface"),
            arguments: [objectValue, interfaceTypeExpr, ifaceSlotExpr],
            result: registerIfaceResult,
            canThrow: false,
            thrownResult: nil
        ))

        // Sorted by slot number for deterministic codegen: vtableSlots is a
        // Dictionary, whose iteration order is unspecified and can vary
        // between process invocations (or even between two compilations in
        // the same process, depending on insertion history) even for the
        // same key set. Iterating it directly here previously went
        // unnoticed because so few nominals reached this registration path
        // with more than one interface method — StringBuilder's Appendable
        // conformance (BUG-166) was the first to make it visible, as two
        // otherwise-identical compilations of the same source emitted their
        // three kk_object_register_itable_method calls in different orders.
        for (methodSymbol, methodSlotInt) in kirItableMethodEntries(
            for: interfaceSymbol,
            interfaceLayout: interfaceLayout,
            sema: sema,
            interner: interner
        ) {
            let implementationSymbol = kirFindOverrideMethod(
                for: methodSymbol,
                in: nominalSymbol,
                sema: sema,
                interner: interner
            ) ?? methodSymbol
            let bridgeSymbol = itableBridgeSymbolForMethod(
                interfaceMethod: methodSymbol,
                implementation: implementationSymbol,
                nominalSymbol: nominalSymbol,
                driver: driver,
                arena: arena,
                sema: sema,
                interner: interner
            )
            let methodSlot = Int64(methodSlotInt)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(bridgeSymbol), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(bridgeSymbol)))

            let registerMethodResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_register_itable_method"),
                arguments: [objectValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerMethodResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    // BUG-141: also register interface property getters into the itable.
    appendObjectItablePropertyGetterRegistrations(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
}

/// Returns the interface methods that must be registered for dynamic itable dispatch.
///
/// BUG-200: bundled library metadata currently omits the compiler-residual
/// covariant `MutableIterable.iterator(): MutableIterator<T>` entry from the
/// `MutableIterable` vtable layout. The source class still advertises the
/// interface and its implementation, so add that exact method at slot zero
/// until the shared residual layout can carry the covariant member itself.
func kirItableMethodEntries(
    for interfaceSymbol: SymbolID,
    interfaceLayout: NominalLayout,
    sema: SemaModule,
    interner: StringInterner
) -> [(methodSymbol: SymbolID, methodSlot: Int)] {
    var methods = interfaceLayout.vtableSlots
    let mutableIterableFQName = ["kotlin", "collections", "MutableIterable"].map(interner.intern)
    guard let symbol = sema.symbols.symbol(interfaceSymbol),
          symbol.fqName == mutableIterableFQName
    else {
        return methods
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value < rhs.value
            }
            .map { (methodSymbol: $0.key, methodSlot: $0.value) }
    }

    let iteratorFQName = mutableIterableFQName + [interner.intern("iterator")]
    if let iteratorSymbol = sema.symbols.lookup(fqName: iteratorFQName),
       methods[iteratorSymbol] == nil
    {
        methods[iteratorSymbol] = 0
    }
    return methods
        .sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value < rhs.value
        }
        .map { (methodSymbol: $0.key, methodSlot: $0.value) }
}

/// Interfaces reachable from `nominalSymbol` through the whole supertype
/// closure, including those implemented by base classes rather than by the
/// nominal itself. The itable layout assigns slots for exactly this set
/// (`LayoutSynthesis.collectInterfaceSupertypes`), so instances must register
/// every one of them to be dispatchable through an interface static type.
func kirTransitiveInterfaceSupertypes(
    of nominalSymbol: SymbolID,
    sema: SemaModule
) -> [SymbolID] {
    var stack = sema.symbols.directSupertypes(for: nominalSymbol)
    var visited: Set<SymbolID> = []
    var interfaces: [SymbolID] = []

    while let current = stack.popLast() {
        guard visited.insert(current).inserted else {
            continue
        }
        if sema.symbols.symbol(current)?.kind == .interface {
            interfaces.append(current)
        }
        stack.append(contentsOf: sema.symbols.directSupertypes(for: current))
    }

    return interfaces.sorted { $0.rawValue < $1.rawValue }
}

/// Resolves the implementation an instance of `nominalSymbol` must expose for
/// `interfaceMethod`. The override may live on the nominal itself or on any of
/// its base classes (`class IntBox : AbstractBox<Int>()` inheriting
/// `AbstractBox.get`), so the class chain is walked most-derived first.
func kirFindOverrideMethod(
    for interfaceMethod: SymbolID,
    in nominalSymbol: SymbolID,
    sema: SemaModule,
    interner _: StringInterner
) -> SymbolID? {
    var visited: Set<SymbolID> = []
    var current: SymbolID? = nominalSymbol
    while let nominal = current, visited.insert(nominal).inserted {
        if let found = kirFindMatchingMethod(
            matching: interfaceMethod,
            on: nominal,
            sema: sema
        ) {
            return found
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }

    // Interface default implementations live on the interface itself
    // (`Ranked.compareTo` for `Comparable.compareTo`). Prefer the closest
    // owner so a residual `Comparable.compareTo` does not win over Ranked.
    var bestDefault: (distance: Int, symbol: SymbolID)?
    for interfaceSymbol in kirTransitiveInterfaceSupertypes(of: nominalSymbol, sema: sema) {
        guard let found = kirFindMatchingMethod(
            matching: interfaceMethod,
            on: interfaceSymbol,
            sema: sema,
            requireSourceBacked: true
        ) else {
            continue
        }
        let distance = kirNominalDistance(from: nominalSymbol, to: interfaceSymbol, sema: sema) ?? Int.max
        if let currentBest = bestDefault {
            if distance < currentBest.distance {
                bestDefault = (distance, found)
            }
        } else {
            bestDefault = (distance, found)
        }
    }
    return bestDefault?.symbol
}

private func kirFindMatchingMethod(
    matching interfaceMethod: SymbolID,
    on nominal: SymbolID,
    sema: SemaModule,
    requireSourceBacked: Bool = false
) -> SymbolID? {
    guard let methodSym = sema.symbols.symbol(interfaceMethod),
          let ownerSym = sema.symbols.symbol(nominal)
    else {
        return nil
    }

    let interfaceParameterTypes = sema.symbols.functionSignature(for: interfaceMethod)?.parameterTypes
    let interfaceParamCount = interfaceParameterTypes?.count
    let children = sema.symbols.children(ofFQName: ownerSym.fqName)
    var firstCandidate: SymbolID?
    var arityMatch: SymbolID?
    for candidate in children {
        guard let candidateSym = sema.symbols.symbol(candidate),
              candidateSym.kind == .function,
              candidateSym.name == methodSym.name,
              sema.symbols.parentSymbol(for: candidate) == nominal
        else {
            continue
        }
        // Interface fallback must use a body-bearing source declaration;
        // synthetic residual declarations are not executable defaults.
        if requireSourceBacked, !sema.symbols.isSourceBackedSymbol(candidate) {
            continue
        }
        if firstCandidate == nil {
            firstCandidate = candidate
        }
        let candidateParams = sema.symbols.functionSignature(for: candidate)?.parameterTypes ?? []
        // Prefer a full parameter-type match so same-arity overloads
        // (e.g. StringBuilder.append(Char) vs append(String)) land in
        // the correct itable slot. Type parameters are wildcards.
        if let interfaceParameterTypes,
           kirOverrideParameterTypesMatch(
               candidateParameterTypes: candidateParams,
               interfaceParameterTypes: interfaceParameterTypes,
               types: sema.types
           )
        {
            return candidate
        }
        // BUG-166: fall back to arity matching when type IDs don't
        // line up (e.g. untracked signatures), then to first name match.
        if arityMatch == nil,
           let interfaceParamCount,
           candidateParams.count == interfaceParamCount
        {
            arityMatch = candidate
        }
    }
    return arityMatch ?? firstCandidate
}

/// A class implementing an interface can declare several overloads sharing
/// the interface method's name (StringBuilder has multiple `append`
/// overloads for one `Appendable.append` per arity) — `lookupAll(fqName:)`
/// returns all of them, so `kirFindOverrideMethod` must pick the one whose
/// signature actually matches `interfaceMethod`, not just the first
/// same-named function on the class. Type parameters are treated as
/// wildcards on either side since a generic interface method's parameter
/// type may not be reified the same way on the implementing side.
private func kirOverrideParameterTypesMatch(
    candidateParameterTypes: [TypeID],
    interfaceParameterTypes: [TypeID],
    types: TypeSystem
) -> Bool {
    guard candidateParameterTypes.count == interfaceParameterTypes.count else { return false }
    for (candidateType, interfaceType) in zip(candidateParameterTypes, interfaceParameterTypes) {
        if case .typeParam = types.kind(of: candidateType) { continue }
        if case .typeParam = types.kind(of: interfaceType) { continue }
        if candidateType != interfaceType { return false }
    }
    return true
}

func kirSuperclass(of nominalSymbol: SymbolID, sema: SemaModule) -> SymbolID? {
    sema.symbols.directSupertypes(for: nominalSymbol).first { superSymbol in
        switch sema.symbols.symbol(superSymbol)?.kind {
        case .class, .enumClass, .object:
            true
        default:
            false
        }
    }
}

private func kirNominalDistance(
    from nominalSymbol: SymbolID,
    to targetSymbol: SymbolID,
    sema: SemaModule
) -> Int? {
    var queue: [(symbol: SymbolID, distance: Int)] = [(nominalSymbol, 0)]
    var visited: Set<SymbolID> = []

    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard visited.insert(current.symbol).inserted else {
            continue
        }
        if current.symbol == targetSymbol {
            return current.distance
        }
        for superSymbol in sema.symbols.directSupertypes(for: current.symbol) {
            guard let superInfo = sema.symbols.symbol(superSymbol) else {
                continue
            }
            switch superInfo.kind {
            case .class, .object, .enumClass, .annotationClass, .interface:
                queue.append((superSymbol, current.distance + 1))
            default:
                continue
            }
        }
    }

    return nil
}
