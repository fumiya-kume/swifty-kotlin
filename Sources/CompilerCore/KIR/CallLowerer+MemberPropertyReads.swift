/// Member-property read helpers (object members, object-literal stored
/// properties, generic stored properties, enum entry properties, external
/// members, class-name member values, const-folding) split out of
/// `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    /// BUG-227: whether a class member-property read/write should dispatch
    /// through the getter/setter accessor slot LayoutSynthesis assigned it,
    /// rather than the statically-resolved declaration's own field
    /// offset/accessor — mirroring `resolveVtableDispatchKind`'s identical
    /// rule for ordinary method calls: open/override members whose owner
    /// currently has known subtypes are eligible, since a receiver typed as a
    /// leaf (subtype-less) class can never actually hold a more-derived
    /// override at runtime. Abstract members are always eligible because
    /// their declaration has no concrete field/accessor implementation to
    /// read directly, including when implementations live outside this
    /// compilation unit.
    ///
    /// `super`-qualified access is always excluded — `super.p` must keep
    /// reading/writing the syntactically-named class's own implementation,
    /// never the runtime type's override (BUG-228 tracks that `super.p`
    /// already resolves to the wrong symbol upstream in Sema; this guard
    /// keeps that pre-existing bug from becoming a *worse*, dynamically wrong
    /// one once accessors are virtually dispatched).
    func tryResolvePropertyAccessorVirtualDispatch(
        propertySymbol: SymbolID,
        receiverExpr: ExprID,
        accessorKind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule
    ) -> (accessorSymbol: SymbolID, dispatch: KIRDispatchKind)? {
        if case .superRef = ast.arena.expr(receiverExpr) {
            return nil
        }
        guard let propInfo = sema.symbols.symbol(propertySymbol),
              propInfo.flags.contains(.openType)
                  || propInfo.flags.contains(.abstractType)
                  || propInfo.flags.contains(.overrideMember),
              let ownerID = sema.symbols.parentSymbol(for: propertySymbol),
              sema.symbols.symbol(ownerID)?.kind == .class,
              (propInfo.flags.contains(.abstractType)
                  || !sema.symbols.directSubtypes(of: ownerID).isEmpty),
              let layout = sema.symbols.nominalLayout(for: ownerID)
        else {
            return nil
        }
        let accessorSymbol = SyntheticSymbolScheme.propertyAccessorSymbol(for: propertySymbol, kind: accessorKind)
        guard let slot = layout.vtableSlots[accessorSymbol] else {
            return nil
        }
        return (accessorSymbol, .vtable(slot: slot))
    }

    func tryLowerObjectMemberPropertyRead(
        _ exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let chosenSym = sema.bindings.callBindings[exprID]?.chosenCallee
        let valueSym = chosenSym ?? sema.bindings.identifierSymbol(for: exprID)
        guard let valueSym,
              let info = sema.symbols.symbol(valueSym),
              info.kind == .property,
              let parent = sema.symbols.parentSymbol(for: valueSym),
              sema.symbols.symbol(parent)?.kind == .object
        else { return nil }
        if info.flags.contains(.constValue),
           let constant = sema.symbols.constValueExprKind(for: valueSym)
        {
            let propType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSym)
                ?? sema.types.anyType
            let id = arena.appendExpr(constant, type: propType)
            instructions.append(.constValue(result: id, value: constant))
            return id
        }
        let knownNames = KnownCompilerNames(interner: interner)
        if let parentInfo = sema.symbols.symbol(parent),
           parentInfo.name == knownNames.dispatchers
        {
            let runtimeCallee: InternedString
            switch interner.resolve(info.name) {
            case "Default":
                runtimeCallee = interner.intern("kk_dispatcher_default")
            case "IO":
                runtimeCallee = interner.intern("kk_dispatcher_io")
            case "Main":
                runtimeCallee = interner.intern("kk_dispatcher_main")
            default:
                return nil
            }
            let result = arena.appendTemporary(type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // STDLIB-581: Charsets.UTF_8 / ISO_8859_1 / US_ASCII / UTF_16 / ...
        if let parentInfo = sema.symbols.symbol(parent),
           parentInfo.name == knownNames.charsets
        {
            let runtimeCallee = interner.intern("__kk_charset_\(interner.resolve(info.name).lowercased())")
            let result = arena.appendTemporary(type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if let parentInfo = sema.symbols.symbol(parent),
           interner.resolve(parentInfo.name) == "NormalizationForms"
        {
            let runtimeCallee = interner.intern("__kk_normalization_form_\(interner.resolve(info.name).lowercased())")
            let result = arena.appendTemporary(type: sema.bindings.exprTypes[exprID]
                    ?? sema.symbols.propertyType(for: valueSym)
                    ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let propType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: valueSym)
            ?? sema.types.anyType
        let id = arena.appendExpr(.symbolRef(valueSym), type: propType)
        instructions.append(.loadGlobal(result: id, symbol: valueSym))
        return wrapLateinitReadIfNeeded(
            id,
            symbol: valueSym,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func tryLowerObjectLiteralStoredPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              sema.bindings.isObjectLiteralPropertySymbol(propertySymbol)
        else {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        if objectLiteralPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema) {
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.call(
                symbol: propertySymbol,
                callee: interner.intern("get"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Object-literal properties don't currently get a dedicated backing-field
        // symbol from ExprTypeChecker+ObjectLiteralInference.swift's header
        // collection (unlike ordinary class members), so `backingFieldSymbol(for:)`
        // is always nil here today and this falls back to `propertySymbol`
        // unchanged. Kept for consistency with every other field-offset lookup
        // in the codebase (CallLowerer+MemberAssignment.swift,
        // tryLowerStoredMemberPropertyRead, the lateinit branch in
        // KIRLoweringDriver+...+ConstructorsAndInitializers.swift) so this
        // doesn't silently break if object literals ever gain backing fields.
        guard let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                  sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
              ]
        else {
            return nil
        }

        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [loweredReceiverID, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func tryLowerStoredMemberPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // `object` member properties never reach this point: they're always
        // intercepted earlier by `tryLowerObjectMemberPropertyRead`, which
        // reads them from their global slot via `loadGlobal` (mirroring how
        // `lowerMemberAssignExpr`/`lowerMemberCompoundAssignExpr` write them).
        // Restricting this guard to nominal instance types keeps the read and
        // write sides symmetric instead of relying on call-order to keep a
        // dead field-offset arm harmless.
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID)
                  ?? sema.bindings.callBindings[exprID]?.chosenCallee,
              sema.symbols.symbol(propertySymbol)?.kind == .property,
              let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .class || ownerInfo.kind == .interface
                  || ownerInfo.kind == .enumClass || ownerInfo.kind == .annotationClass
        else {
            return nil
        }

        // Array-like types (Array, IntArray, LongArray, etc.) expose
        // properties such as `size` via runtime helper functions rather than
        // object field layout, so let the collection fallback lower them.
        let knownNames = KnownCompilerNames(interner: interner)
        if knownNames.isArrayLikeName(ownerInfo.name) {
            return nil
        }

        // HashSet inherits synthetic collection properties while its storage is
        // a RuntimeSetBox, not a nominal object-field array. Keep size and
        // isEmpty on the shared collection dispatch path for the source-backed
        // HashSet surface, including when the receiver comes from a .kklib.
        let hashSetFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("HashSet")
        ]
        if let propertyInfo = sema.symbols.symbol(propertySymbol),
           propertyInfo.name == interner.intern("size")
               || propertyInfo.name == interner.intern("isEmpty"),
           let receiverType = arena.exprType(loweredReceiverID),
           let (_, receiverSymbol) = resolveClassTypeSymbol(
               sema.types.makeNonNullable(receiverType), sema: sema
           ),
           receiverSymbol.fqName == hashSetFQName
        {
            return nil
        }

        // Runtime-backed interface properties (for example Collection.size)
        // may now carry a bundled source declaration while retaining their
        // external ABI link. Keep those reads on the direct bridge path below;
        // registering them as source property getters would require runtime
        // boxes to provide an itable getter they do not own.
        if let externalLinkName = sema.symbols.externalLinkName(for: propertySymbol),
           !externalLinkName.isEmpty
        {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.anyType

        // KSP-928: an abstract/open class property is a getter dispatch point,
        // not an instance field or a direct abstract getter stub. In
        // particular, AbstractMap's skeletal methods must observe a concrete
        // subclass's `entries` override.
        if ownerInfo.kind == .class,
           !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
           let propertyInfo = sema.symbols.symbol(propertySymbol),
           let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
               SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
           ],
           propertyInfo.flags.contains(.abstractType)
               || propertyInfo.flags.contains(.openType)
        {
            let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.virtualCall(
                symbol: getterSymbol,
                callee: interner.intern("get"),
                receiver: loweredReceiverID,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil,
                dispatch: .vtable(slot: getterSlot)
            ))
            return result
        }

        if memberPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema) {
            if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .getter,
                ast: ast,
                sema: sema
            ) {
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.virtualCall(
                    symbol: accessorSymbol,
                    callee: interner.intern("get"),
                    receiver: loweredReceiverID,
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatch
                ))
                return result
            }
            let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            // Native interface getters are runtime bridges whose runtime boxes
            // do not provide an itable property slot. Keep those accessors direct;
            // imported Kotlin getters with kk_fn_* links remain on the dynamic
            // itable path below.
            let getterUsesRuntimeBridge = kirIsRuntimeBridgedCallee(getterSymbol, sema: sema)
            if ownerInfo.kind != .interface || getterUsesRuntimeBridge {
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: getterSymbol,
                    callee: interner.intern("get"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if ownerInfo.kind == .interface {
            return tryLowerInterfaceItablePropertyGetterRead(
                propertySymbol: propertySymbol,
                loweredReceiverID: loweredReceiverID,
                resultType: resultType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        if ownerInfo.kind == .enumClass,
           let propertyInfo = sema.symbols.symbol(propertySymbol),
           propertyInfo.kind == .property || propertyInfo.kind == .field
        {
            let propertyName = propertyInfo.name
            let helperName = interner.intern("$enumConstructorProperty$\(ownerSymbol.rawValue)$\(interner.resolve(propertyName))")
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: helperName,
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // BUG-227: a stored open/abstract/override property whose owner has
        // known subtypes must dispatch through its getter's vtable slot — the
        // field offset below is only this *declaration's own* storage, which
        // is correct only when no runtime-type override can be in play.
        if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
            propertySymbol: propertySymbol,
            receiverExpr: receiverExpr,
            accessorKind: .getter,
            ast: ast,
            sema: sema
        ) {
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.virtualCall(
                symbol: accessorSymbol,
                callee: interner.intern("get"),
                receiver: loweredReceiverID,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil,
                dispatch: dispatch
            ))
            return result
        }

        guard let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
            sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        ] else {
            return nil
        }

        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [loweredReceiverID, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// BUG-141: an interface has no per-instance storage of its own, so a
    /// stored/abstract interface property read through an interface-typed
    /// receiver cannot use a concrete field offset. Dispatch through the
    /// interface's itable to the implementing type's getter, mirroring how
    /// interface member functions are dispatched (see resolveItableDispatch).
    ///
    /// BUG-187: the same applies to an implicit-receiver read (`rank` inside an
    /// interface default method body), which otherwise calls the interface's own
    /// abstract getter and observes its `null` placeholder body.
    func tryLowerInterfaceItablePropertyGetterRead(
        propertySymbol: SymbolID,
        loweredReceiverID: KIRExprID,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // Synthetic stdlib interface properties (e.g. `Collection.size`) are
        // backed by runtime objects that do not register itable property
        // getters, so their reads remain on the runtime fallback path.
        // KSP-724: `CharSequence.length` is a source-backed interface property,
        // so its `declSite` is set and it reaches the normal itable path along
        // with other bundled interface properties.
        guard let propertyInfo = sema.symbols.symbol(propertySymbol),
              let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .interface,
              (propertyInfo.declSite != nil
                  || propertyInfo.flags.contains(.importedLibrary)),
              let methodSlot = kirInterfacePropertyGetterSlot(
                  interfaceProperty: propertySymbol,
                  interfaceSymbol: ownerSymbol,
                  sema: sema,
                  interner: interner
              )
        else {
            return nil
        }
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: ownerSymbol, sema: sema, interner: interner
        )
        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.virtualCall(
            symbol: getterSymbol,
            callee: interner.intern("get"),
            receiver: loweredReceiverID,
            arguments: [],
            result: result,
            canThrow: false,
            thrownResult: nil,
            dispatch: .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
        ))
        return result
    }

    func tryLowerMemberPropertyAccessorRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        result: KIRExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              memberPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema)
        else {
            return nil
        }

        if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
            propertySymbol: propertySymbol,
            receiverExpr: receiverExpr,
            accessorKind: .getter,
            ast: ast,
            sema: sema
        ) {
            instructions.append(.virtualCall(
                symbol: accessorSymbol,
                callee: interner.intern("get"),
                receiver: loweredReceiverID,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil,
                dispatch: dispatch
            ))
            return result
        }

        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        instructions.append(.call(
            symbol: getterSymbol,
            callee: interner.intern("get"),
            arguments: [loweredReceiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func tryLowerEnumEntryPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "name" || calleeStr == "ordinal" else { return nil }
        let resultType = sema.bindings.exprTypes[exprID]
            ?? (calleeStr == "name"
                ? sema.types.stringType
                : sema.types.make(.primitive(.int, .nonNull)))
        if case let .symbolRef(entrySym) = arena.expr(loweredReceiverID),
           isEnumEntryField(entrySym, sema: sema),
           let entryInfo = sema.symbols.symbol(entrySym)
        {
            let helperName = calleeStr == "name"
                ? NameMangler.enumEntryNameHelperName(for: entryInfo, interner: interner)
                : NameMangler.enumEntryOrdinalHelperName(for: entryInfo, interner: interner)
            let ownerFQName = Array(entryInfo.fqName.dropLast())
            let helperSymbol = sema.symbols.lookupAll(fqName: ownerFQName + [helperName]).first { id in
                sema.symbols.symbol(id).map { $0.kind == .function } ?? false
            }
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.call(
                symbol: helperSymbol,
                callee: helperName,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // The receiver isn't a compile-time-known entry (e.g. a reassigned
        // `var` or a function parameter) — fall back to a dynamic lookup
        // keyed off the receiver's own runtime value instead of returning
        // nil. Returning nil here would fall through to the generic
        // member-call path, which silently drops the receiver argument for
        // this synthetic property (it has no FunctionSignature.receiverType
        // for appendReceiverToMemberArguments to key off), producing an
        // unresolved "name"/"ordinal" external symbol at link time.
        guard let receiverType = sema.bindings.exprTypes[receiverExpr],
              let (_, classSym) = resolveClassTypeSymbol(receiverType, sema: sema),
              classSym.kind == .enumClass
        else {
            return nil
        }
        if calleeStr == "ordinal" {
            // Enum values are represented as their boxed ordinal (see
            // DataEnumSealedSynthesisPass's $enumOrdinalToName, which unboxes
            // its receiver-typed parameter the same way), so `.ordinal` on a
            // dynamic receiver is just that unboxing.
            return emitNonThrowingCall(
                callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
                arg: loweredReceiverID,
                resultType: resultType,
                arena: arena,
                into: &instructions
            )
        }
        // "name": the $enumOrdinalToName helper doesn't exist yet at
        // KIR-build time (DataEnumSealedSynthesisPass synthesizes it during
        // the later Lowering phase) — emit a receiverless-named placeholder
        // call carrying the receiver as its sole argument, matching what
        // EnumNameAccessLoweringPass rewrites into a real call to that
        // helper once it exists.
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: calleeName,
            arguments: [loweredReceiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func tryLowerExternalMemberPropertyRead(
        _ exprID: ExprID,
        loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
              let externalLinkName = sema.symbols.externalLinkName(for: propertySymbol),
              !externalLinkName.isEmpty
        else {
            return nil
        }

        // A source-backed Collection.size declaration is inherited by concrete
        // collection receivers. Let the normal collection dispatch preserve
        // List/Set/EnumEntries-specific bridges instead of taking the generic
        // Collection ABI link here.
        if shouldDeferCollectionSizePropertyRead(
            propertySymbol,
            receiverExpr: receiverExpr,
            sema: sema,
            interner: interner
        ) {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.anyType
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: propertySymbol,
            callee: interner.intern(externalLinkName),
            arguments: [loweredReceiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return wrapLateinitReadIfNeeded(
            result,
            symbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func shouldDeferCollectionSizePropertyRead(
        _ propertySymbol: SymbolID,
        receiverExpr: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let property = sema.symbols.symbol(propertySymbol),
              property.name == interner.intern("size"),
              let ownerID = sema.symbols.parentSymbol(for: propertySymbol),
              sema.symbols.symbol(ownerID)?.fqName == [
                  interner.intern("kotlin"),
                  interner.intern("collections"),
                  interner.intern("Collection"),
              ],
              let receiverType = sema.bindings.exprTypes[receiverExpr]
        else {
            return false
        }
        return unresolvedCollectionMemberCallee(
            memberName: "size",
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) != nil
    }

    func objectLiteralPropertyUsesAccessor(
        _ propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            return propertyDecl.getter != nil || propertyDecl.delegateExpression != nil
        }
        return false
    }

    func memberPropertyUsesAccessor(
        _ propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        if sema.symbols.propertyHasCustomGetter(for: propertySymbol) {
            return true
        }
        if sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol) != nil {
            return true
        }
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            if let getter = propertyDecl.getter {
                return getter.body != .unit
            }
            return propertyDecl.delegateExpression != nil
        }
        return false
    }

    func tryLowerClassNameMemberValueExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // The receiver may itself be a qualified member-access chain (e.g. the
        // `Base64.PaddingOption` prefix of `Base64.PaddingOption.ABSENT`, where
        // `PaddingOption` is nested inside `Base64`), not just a bare name
        // reference. `identifierSymbol` already carries the resolved nominal
        // type regardless of the receiver expression's AST shape -- except when
        // Sema itself resolved the receiver via the raw-name scope-lookup
        // fallback in `classNameReceiverNominalSymbol`
        // (CallTypeChecker+MemberCallInferenceRegularResolution.swift), which
        // never binds anything to the receiver expression itself. Mirror that
        // same fallback here (by short name, over the global symbol table
        // rather than a scope, since KIR lowering has no scope stack) so a
        // bare-nameRef receiver like `Outer` in `Outer.Color` still qualifies.
        guard args.isEmpty,
              let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverExpr)
                  ?? bareNameRefClassLikeSymbol(receiverExpr, ast: ast, sema: sema),
              let receiverSymbol = sema.symbols.symbol(receiverSymbolID),
              receiverSymbol.kind == .class || receiverSymbol.kind == .interface
                  || receiverSymbol.kind == .enumClass || receiverSymbol.kind == .annotationClass
        else {
            return nil
        }
        // A qualified static member (enum entry, nested object, const val) is
        // sometimes bound via `identifierSymbol` and sometimes via a 0-arg
        // `CallBinding` (the same resolution path ordinary property reads use)
        // depending on how the type checker resolved the member — both carry
        // the same target symbol, so accept either. A *further* nested-type
        // qualifier segment (e.g. the `Color` in `Outer.Color.values()`) gets
        // neither: Sema resolves a class-name-receiver call like
        // `Outer.Color.values()` directly from `Outer`'s FQ name
        // (CallTypeChecker+MemberCallInferenceRegularResolution.swift) without
        // ever independently type-checking the `Outer.Color` prefix as its own
        // expression, so no binding of any kind exists for it. Reconstruct the
        // same answer directly from the symbol table.
        guard let valueSymbolID = sema.bindings.identifierSymbol(for: exprID)
            ?? sema.bindings.callBindings[exprID]?.chosenCallee
            ?? nestedClassLikeMemberSymbol(exprID, ownerSymbol: receiverSymbolID, ast: ast, sema: sema),
            let valueSymbol = sema.symbols.symbol(valueSymbolID)
        else {
            return nil
        }

        switch valueSymbol.kind {
        case .property where valueSymbol.flags.contains(.static)
            && receiverSymbol.kind == .enumClass:
            // Enum static properties such as `Color.entries` are represented
            // by the enum lowering pass, not by an instance field or an enum
            // constructor property. Preserve the property symbol so
            // EnumEntriesLoweringPass can route `entries` to `entries$get`.
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        case .property where valueSymbol.flags.contains(.constValue):
            guard let constant = sema.symbols.constValueExprKind(for: valueSymbolID) else {
                return nil
            }
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(constant, type: valueType)
            instructions.append(.constValue(result: valueID, value: constant))
            return valueID

        case .field:
            guard isEnumEntryField(valueSymbolID, sema: sema) else {
                return nil
            }
            let valueType = sema.bindings.exprTypes[exprID]
                ?? sema.symbols.propertyType(for: valueSymbolID)
                ?? sema.types.anyType
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        case .object, .class, .interface, .enumClass, .annotationClass:
            // The "member" is itself a further nominal-type qualifier, e.g. the
            // `Color` in `Outer.Color.values()`. Unlike `.object`, it isn't a
            // singleton with an instance accessor, but it must short-circuit
            // the same way: otherwise this falls through to the generic
            // `driver.lowerExpr(receiverExpr, ...)` path below, which emits a
            // `.call` using the qualifier's bare short name expecting a 0-arg
            // instance accessor that was never synthesized, leaving an
            // undefined symbol at link time.
            let valueType = sema.bindings.exprTypes[exprID] ?? sema.types.make(.classType(ClassType(
                classSymbol: valueSymbolID,
                args: [],
                nullability: .nonNull
            )))
            let valueID = arena.appendExpr(.symbolRef(valueSymbolID), type: valueType)
            instructions.append(.constValue(result: valueID, value: .symbolRef(valueSymbolID)))
            return valueID

        default:
            return nil
        }
    }

    /// Resolves a further nested-type qualifier segment (e.g. the `Color` in
    /// `Outer.Color.values()`, once `Outer` is already known to be
    /// `ownerSymbol`) directly from the symbol table, for the case described
    /// above `tryLowerClassNameMemberValueExpr`'s callers where Sema left no
    /// binding at all for this expression. Mirrors the `nestedOwnerSymbols`
    /// lookup in `CallTypeChecker+MemberCallInferenceRegularResolution.swift`.
    private func nestedClassLikeMemberSymbol(_ expr: ExprID, ownerSymbol: SymbolID, ast: ASTModule, sema: SemaModule) -> SymbolID? {
        guard case let .memberCall(_, calleeName, _, memberArgs, _) = ast.arena.expr(expr), memberArgs.isEmpty,
              let owner = sema.symbols.symbol(ownerSymbol)
        else {
            return nil
        }
        return sema.symbols.lookupAll(fqName: owner.fqName + [calleeName]).first { candidate in
            guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                return false
            }
            switch sema.symbols.symbol(candidate)?.kind {
            case .class, .interface, .enumClass, .object, .annotationClass:
                return true
            default:
                return false
            }
        }
    }

    /// Resolves a bare `nameRef` receiver (e.g. `Outer` in `Outer.Color`) to a
    /// class/interface/enum-class symbol by short name, for the cases where
    /// Sema's own `classNameReceiverNominalSymbol` fallback
    /// (CallTypeChecker+MemberCallInferenceRegularResolution.swift) resolved it
    /// via a raw-name scope lookup instead of `bindIdentifier`, leaving no
    /// `identifierSymbol` binding for KIR lowering to read. A global
    /// short-name lookup can't see local shadowing the way Sema's scope lookup
    /// could, but by this point in a member-access chain the receiver can only
    /// be a nominal type reference, not a local, so the ambiguity that matters
    /// for Sema's lookup doesn't apply here.
    private func bareNameRefClassLikeSymbol(_ expr: ExprID, ast: ASTModule, sema: SemaModule) -> SymbolID? {
        guard case let .nameRef(name, _) = ast.arena.expr(expr) else {
            return nil
        }
        return sema.symbols.lookupByShortName(name).first { candidate in
            switch sema.symbols.symbol(candidate)?.kind {
            case .class, .interface, .enumClass, .annotationClass:
                true
            default:
                false
            }
        }
    }

    func isEnumEntryField(_ fieldSymbol: SymbolID, sema: SemaModule) -> Bool {
        if let parentSymbol = sema.symbols.parentSymbol(for: fieldSymbol),
           sema.symbols.symbol(parentSymbol)?.kind == .enumClass
        {
            return true
        }
        guard let field = sema.symbols.symbol(fieldSymbol),
              field.kind == .field,
              field.fqName.count >= 2
        else {
            return false
        }
        let ownerFQName = Array(field.fqName.dropLast())
        return sema.symbols.lookupAll(fqName: ownerFQName).contains { candidate in
            sema.symbols.symbol(candidate)?.kind == .enumClass
        }
    }
}
