import Foundation

/// Synthetic stdlib stubs for kotlin's not-yet-implemented helper, kotlin.io.println (0-arg), and kotlin.io.readLine (STDLIB-063).
/// These stubs enable name resolution and type checking; runtime behavior is implemented in Runtime.
extension DataFlowSemaPhase {
    func registerSyntheticTODOAndIOStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let packageSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        registerSyntheticPreconditionFunction(
            named: "TODO",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [],
            returnType: types.nothingType,
            externalLinkName: "kk_todo_noarg",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticPreconditionFunction(
            named: "TODO",
            packageFQName: kotlinPkg,
            packageSymbol: packageSymbol,
            parameters: [(name: "reason", type: types.stringType)],
            returnType: types.nothingType,
            externalLinkName: "kk_todo",
            symbols: symbols,
            interner: interner
        )

        let kotlinIOPkg = ensureSyntheticPackageHierarchy(fqName: [interner.intern("kotlin"), interner.intern("io")], symbols: symbols)

        registerSyntheticTopLevelFunction(
            named: "println",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_println_newline",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "println",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "message", type: types.makeNullable(types.anyType))],
            returnType: types.unitType,
            externalLinkName: "kk_println_any",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "print",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_print_noarg",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "print",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "message", type: types.makeNullable(types.anyType))],
            returnType: types.unitType,
            externalLinkName: "kk_print_any",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "readLine",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.makeNullable(types.stringType),
            externalLinkName: "kk_readline",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "readln",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_readln",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "readlnOrNull",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: types.makeNullable(types.stringType),
            externalLinkName: "kk_readlnOrNull",
            symbols: symbols,
            interner: interner
        )

        // --- Sequence factory functions (STDLIB-097) ---
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        _ = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticSequenceBuilderStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // --- Grouping type (STDLIB-285/286) ---
        registerSyntheticGroupingStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticVarargFunction(
            named: "sequenceOf",
            packageFQName: kotlinSequencesPkg,
            returnType: types.anyType,
            externalLinkName: "kk_sequence_of",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-277: emptySequence<T>()
        registerSyntheticTopLevelFunction(
            named: "emptySequence",
            packageFQName: kotlinSequencesPkg,
            parameters: [],
            returnType: types.anyType,
            externalLinkName: "kk_empty_sequence",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "generateSequence",
            packageFQName: kotlinSequencesPkg,
            parameters: [
                (name: "seed", type: types.anyType),
                (name: "nextFunction", type: types.anyType),
            ],
            returnType: types.anyType,
            externalLinkName: "kk_sequence_generate",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-331/564: iterator {} builder → Iterator<T>
        // Registered with SequenceScope<T> receiver so yield() resolves inside the lambda.
        registerSyntheticIteratorBuilderStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-330: sequence { yield(x) } builder
        registerSyntheticSequenceBuilderStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticSequenceJoinToStringMember(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg
        )
        registerSyntheticSequenceTerminalMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg
        )

        // --- kotlin.system package functions (STDLIB-131/132) ---
        let kotlinSystemPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("system")],
            symbols: symbols
        )

        registerSyntheticTopLevelFunction(
            named: "exitProcess",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "status", type: types.intType)],
            returnType: types.nothingType,
            externalLinkName: "kk_system_exitProcess",
            symbols: symbols,
            interner: interner
        )

        let blockFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))

        registerSyntheticTopLevelFunction(
            named: "measureTimeMillis",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "block", type: blockFunctionType)],
            returnType: types.longType,
            externalLinkName: "kk_system_measureTimeMillis",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "measureNanoTime",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "block", type: blockFunctionType)],
            returnType: types.longType,
            externalLinkName: "kk_system_measureNanoTime",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.system.System object (STDLIB-131) ---
        let systemSymbol = ensureSyntheticObjectSymbol(
            named: "System",
            in: kotlinSystemPkg,
            symbols: symbols,
            interner: interner
        )
        let systemType = types.make(.classType(ClassType(
            classSymbol: systemSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(systemType, for: systemSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "currentTimeMillis",
            externalLinkName: "kk_system_currentTimeMillis",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "nanoTime",
            externalLinkName: "kk_system_nanoTime",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.synchronized (STDLIB-325) ---
        registerSyntheticTopLevelFunction(
            named: "synchronized",
            packageFQName: kotlinPkg,
            parameters: [
                (name: "lock", type: types.anyType),
                (name: "block", type: types.anyType),
            ],
            returnType: types.anyType,
            externalLinkName: "kk_synchronized",
            symbols: symbols,
            interner: interner
        )

        // --- java.io.File (STDLIB-320) ---
        let javaIOPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("java"), interner.intern("io")],
            symbols: symbols
        )
        let fileSymbol = ensureClassSymbol(
            named: "File",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileType, for: fileSymbol)

        // File(path: String) constructor
        registerSyntheticConstructor(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            externalLinkName: "kk_file_new",
            parameters: [(name: "path", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // readText(): String
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "readText",
            externalLinkName: "kk_file_readText",
            returnType: types.stringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // writeText(text: String): Unit
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "writeText",
            externalLinkName: "kk_file_writeText",
            returnType: types.unitType,
            parameters: [(name: "text", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // appendText(text: String): Unit
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "appendText",
            externalLinkName: "kk_file_appendText",
            returnType: types.unitType,
            parameters: [(name: "text", type: types.stringType)],
            symbols: symbols,
            interner: interner
        )

        // readLines(): List<String>
        let listOfStringType = makeFileListOfStringType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            name: "readLines",
            externalLinkName: "kk_file_readLines",
            returnType: listOfStringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.time package (STDLIB-230/231/585) ---
        let kotlinTimePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("time")],
            symbols: symbols
        )

        // Register synthetic Duration class (STDLIB-585)
        let durationName = interner.intern("Duration")
        let durationFQName = kotlinTimePkg + [durationName]
        let durationSymbol: SymbolID = if let existing = symbols.lookup(fqName: durationFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: durationName,
                fqName: durationFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: kotlinTimePkg) {
            symbols.setParentSymbol(packageSymbol, for: durationSymbol)
        }

        let durationClassType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(durationClassType, for: durationSymbol)

        // Register Duration.inWholeMilliseconds property (returns Long)
        registerSyntheticDurationMember(
            named: "inWholeMilliseconds",
            externalLinkName: "kk_duration_inWholeMilliseconds",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            isProperty: true
        )

        // Register Duration.inWholeSeconds property (returns Long)
        registerSyntheticDurationMember(
            named: "inWholeSeconds",
            externalLinkName: "kk_duration_inWholeSeconds",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            isProperty: true
        )

        // Register Duration.inWholeMicroseconds property (returns Long)
        registerSyntheticDurationMember(
            named: "inWholeMicroseconds",
            externalLinkName: "kk_duration_inWholeMicroseconds",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            isProperty: true
        )

        // Register Duration.inWholeNanoseconds property (returns Long)
        registerSyntheticDurationMember(
            named: "inWholeNanoseconds",
            externalLinkName: "kk_duration_inWholeNanoseconds",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            isProperty: true
        )

        // Register Duration.toString() (returns String)
        registerSyntheticDurationMember(
            named: "toString",
            externalLinkName: "kk_duration_toString",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // measureTime returns Duration (STDLIB-585)
        let measureTimeBlockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))
        registerSyntheticTopLevelFunction(
            named: "measureTime",
            packageFQName: kotlinTimePkg,
            parameters: [(name: "block", type: measureTimeBlockType)],
            returnType: durationClassType,
            externalLinkName: "kk_measureTime",
            symbols: symbols,
            interner: interner
        )

        // measureTimedValue returns TimedValue (STDLIB-660)
        let timedValueFQName = kotlinTimePkg + [interner.intern("TimedValue")]
        let timedValueType: TypeID
        if let timedValueSymbol = symbols.lookup(fqName: timedValueFQName) {
            timedValueType = types.make(.classType(ClassType(
                classSymbol: timedValueSymbol, args: [], nullability: .nonNull
            )))
        } else {
            timedValueType = types.anyType
        }
        let measureTimedValueBlockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.makeNullable(types.anyType)
        )))
        registerSyntheticTopLevelFunction(
            named: "measureTimedValue",
            packageFQName: kotlinTimePkg,
            parameters: [(name: "block", type: measureTimedValueBlockType)],
            returnType: timedValueType,
            externalLinkName: "kk_measureTimedValue",
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-410: emptyList/emptySet/emptyMap ---
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        //
        // These synthetic registrations return List<Nothing>/Set<Nothing>/Map<Nothing, Nothing>
        // matching Kotlin's actual emptyList<T>() signature where T defaults to Nothing.
        // Because Nothing is the bottom type and List/Set/Map are covariant (out T),
        // List<Nothing> is a subtype of List<T> for all T, so the result is
        // assignable to any typed collection variable via normal covariance.
        //
        // We register phantom type parameters (T for list/set, K/V for map) that do NOT
        // appear in the return type. This lets the OverloadResolver accept explicit type
        // arguments (e.g. emptyList<Int>()) without triggering "Cannot infer type argument"
        // for bare emptyList() calls -- the uninferred-variable check in
        // Resolution+Inference only fires when T is used in the return type or parameters.
        // The CallTypeChecker handles explicit type args to produce the correct collection type.

        let listFQName = kotlinCollectionsPkg + [interner.intern("List")]
        let emptyListReturnType: TypeID
        if let listSymbol = symbols.lookup(fqName: listFQName) {
            emptyListReturnType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(types.nothingType)],
                nullability: .nonNull
            )))
        } else {
            assertionFailure("List interface not found in symbol table; collection stubs must be registered before emptyList")
            emptyListReturnType = types.anyType
        }

        let setFQName = kotlinCollectionsPkg + [interner.intern("Set")]
        let emptySetReturnType: TypeID
        if let setSymbol = symbols.lookup(fqName: setFQName) {
            emptySetReturnType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(types.nothingType)],
                nullability: .nonNull
            )))
        } else {
            assertionFailure("Set interface not found in symbol table; collection stubs must be registered before emptySet")
            emptySetReturnType = types.anyType
        }

        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let emptyMapReturnType: TypeID
        if let mapSymbol = symbols.lookup(fqName: mapFQName) {
            emptyMapReturnType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.out(types.nothingType), .out(types.nothingType)],
                nullability: .nonNull
            )))
        } else {
            assertionFailure("Map interface not found in symbol table; collection stubs must be registered before emptyMap")
            emptyMapReturnType = types.anyType
        }

        // emptyList<T>() -- 1 phantom type parameter
        registerSyntheticEmptyCollectionFunction(
            named: "emptyList",
            packageFQName: kotlinCollectionsPkg,
            returnType: emptyListReturnType,
            typeParamNames: ["T"],
            externalLinkName: "kk_emptyList",
            symbols: symbols,
            interner: interner
        )

        // emptySet<T>() -- 1 phantom type parameter
        registerSyntheticEmptyCollectionFunction(
            named: "emptySet",
            packageFQName: kotlinCollectionsPkg,
            returnType: emptySetReturnType,
            typeParamNames: ["T"],
            externalLinkName: "kk_emptySet",
            symbols: symbols,
            interner: interner
        )

        // emptyMap<K, V>() -- 2 phantom type parameters
        registerSyntheticEmptyCollectionFunction(
            named: "emptyMap",
            packageFQName: kotlinCollectionsPkg,
            returnType: emptyMapReturnType,
            typeParamNames: ["K", "V"],
            externalLinkName: "kk_emptyMap",
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticObjectSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .object,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerSyntheticSequenceJoinToStringMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinSequencesPkg: [InternedString]
    ) {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        let memberName = interner.intern("joinToString")
        let memberFQName = sequenceFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_sequence_joinToString", for: memberSymbol)

        let parameters: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("separator", types.stringType, true),
            ("prefix", types.stringType, true),
            ("postfix", types.stringType, true),
        ]
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: types.stringType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticSystemMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard symbols.symbol(ownerSymbol) != nil else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = symbols.symbol(ownerSymbol)!.fqName + [memberName]
        if symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) != nil {
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func ensureSyntheticPackageHierarchy(
        fqName path: [InternedString],
        symbols: SymbolTable
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for part in path {
            fqName.append(part)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: part,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }

    private func registerSyntheticPreconditionFunction(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticVarargFunction(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        let paramNameID = interner.intern("elements")
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: paramNameID,
            fqName: functionFQName + [paramNameID],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: paramSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.anyType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true]
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    /// Register a synthetic empty-collection factory function (emptyList, emptySet, emptyMap)
    /// with phantom type parameter symbols. The type parameters do NOT appear in the return type
    /// (which is always the Nothing-parameterized collection), so the uninferred-variable check
    /// in Resolution+Inference won't fire. But the OverloadResolver's type-arg-count guard
    /// will accept explicit type arguments (e.g. `emptyList<Int>()`).
    private func registerSyntheticEmptyCollectionFunction(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        typeParamNames: [String],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes.isEmpty
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        // Create phantom type parameter symbols so the OverloadResolver accepts
        // explicit type arguments at call sites.
        var typeParameterSymbols: [SymbolID] = []
        for paramName in typeParamNames {
            let paramNameID = interner.intern(paramName)
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
            typeParameterSymbols.append(typeParamSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticSequenceStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = packageFQName + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        return sequenceSymbol
    }

    private func registerSyntheticSequenceBuilderStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        let sequenceSymbol = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let scopeName = interner.intern("SequenceScope")
        let scopeFQName = kotlinSequencesPkg + [scopeName]
        let scopeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeFQName) {
            scopeSymbol = existing
        } else {
            let sym = symbols.define(
                kind: .class,
                name: scopeName,
                fqName: scopeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinSequencesPkg) {
                symbols.setParentSymbol(packageSymbol, for: sym)
            }
            scopeSymbol = sym
        }
        let scopeTypeParamName = interner.intern("T")
        let scopeTypeParamFQName = scopeFQName + [scopeTypeParamName]
        let scopeTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeTypeParamFQName) {
            scopeTypeParamSymbol = existing
        } else {
            let param = symbols.define(
                kind: .typeParameter,
                name: scopeTypeParamName,
                fqName: scopeTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(scopeSymbol, for: param)
            scopeTypeParamSymbol = param
        }
        types.setNominalTypeParameterSymbols([scopeTypeParamSymbol], for: scopeSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: scopeSymbol)

        let scopeTypeParamType = types.make(.typeParam(TypeParamType(symbol: scopeTypeParamSymbol)))
        let scopeReceiverType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(scopeTypeParamType)],
            nullability: .nonNull
        )))
        registerSequenceScopeMember(
            named: "yield",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "value", type: scopeTypeParamType)],
            returnType: types.unitType,
            externalLinkName: "kk_sequence_builder_yield",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-553: yieldAll(iterable) — yields all elements from a collection/sequence
        // Note: Uses `anyType` because Kotlin's Iterable<T> interface is not yet
        // fully modeled in the type system. The runtime validates the actual collection
        // kind (List, Array, Set, Sequence) and rejects unsupported types at runtime.
        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "elements", type: types.anyType)],
            returnType: types.unitType,
            externalLinkName: "kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )

        let functionName = interner.intern("sequence")
        let functionFQName = kotlinSequencesPkg + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinSequencesPkg) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_sequence_builder_build", for: functionSymbol)

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)

        let builderTypeParamType = types.make(.typeParam(TypeParamType(symbol: functionTypeParamSymbol)))
        let sequenceReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(builderTypeParamType)],
            nullability: .nonNull
        )))
        let builderScopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(builderTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: builderScopeType,
            params: [],
            returnType: types.unitType,
            isSuspend: true
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: functionFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: sequenceReturnType,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    // STDLIB-331/564: iterator {} builder → Iterator<T>
    // Mirrors registerSyntheticSequenceBuilderStub but returns Iterator<T>
    // instead of Sequence<T>, and reuses the SequenceScope<T> receiver for yield().
    private func registerSyntheticIteratorBuilderStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Reuse the SequenceScope class registered by sequence {} builder.
        let scopeName = interner.intern("SequenceScope")
        let scopeFQName = packageFQName + [scopeName]
        let scopeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeFQName) {
            scopeSymbol = existing
        } else {
            let sym = symbols.define(
                kind: .class,
                name: scopeName,
                fqName: scopeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: sym)
            }
            scopeSymbol = sym
        }

        let functionName = interner.intern("iterator")
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_iterator_builder_build", for: functionSymbol)

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)

        let builderTypeParamType = types.make(.typeParam(TypeParamType(symbol: functionTypeParamSymbol)))

        // Return type: Iterator<T>
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        let iteratorInterfaceFQName = kotlinCollectionsPkg + [interner.intern("Iterator")]
        let iteratorReturnType: TypeID
        if let iteratorSymbol = symbols.lookup(fqName: iteratorInterfaceFQName) {
            iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(builderTypeParamType)],
                nullability: .nonNull
            )))
        } else {
            iteratorReturnType = types.anyType
        }

        // Block type: SequenceScope<T>.() -> Unit  (with receiver so yield() resolves)
        let builderScopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(builderTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: builderScopeType,
            params: [],
            returnType: types.unitType,
            isSuspend: true
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: functionFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: iteratorReturnType,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func makeFileListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.stringType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    // MARK: - Grouping (STDLIB-285/286)

    func registerSyntheticGroupingStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let collectionsPkg = kotlinPkg + [interner.intern("collections")]
        _ = ensureSyntheticPackage(fqName: collectionsPkg, symbols: symbols)

        let groupingName = interner.intern("Grouping")
        let groupingFQName = collectionsPkg + [groupingName]
        let groupingSymbol: SymbolID = if let existing = symbols.lookup(fqName: groupingFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: groupingName,
                fqName: groupingFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Type parameters: T (source element type) and K (key type)
        let tParamName = interner.intern("T")
        let tParamFQName = groupingFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let kParamName = interner.intern("K")
        let kParamFQName = groupingFQName + [kParamName]
        let kParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: kParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: kParamName,
                fqName: kParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        types.setNominalTypeParameterSymbols([tParamSymbol, kParamSymbol], for: groupingSymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: groupingSymbol)

        let groupingType = types.make(.classType(ClassType(
            classSymbol: groupingSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Build Map<K, V> return types when Map symbol is available
        let mapName = interner.intern("Map")
        let mapSymbol = symbols.lookup(fqName: collectionsPkg + [mapName])
            ?? symbols.lookupByShortName(mapName).first

        let kTypeParam = types.make(.typeParam(TypeParamType(symbol: kParamSymbol)))

        // eachCount() -> Map<K, Int>
        let eachCountReturnType: TypeID
        if let mapSymbol {
            eachCountReturnType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(kTypeParam), .invariant(types.intType)],
                nullability: .nonNull
            )))
        } else {
            eachCountReturnType = types.anyType
        }
        registerGroupingMember(
            named: "eachCount",
            groupingFQName: groupingFQName,
            groupingSymbol: groupingSymbol,
            receiverType: groupingType,
            parameters: [],
            returnType: eachCountReturnType,
            externalLinkName: "kk_grouping_eachCount",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // fold(initialValue: R, operation: (R, T) -> R) -> Map<K, R>
        let foldOperationType = types.make(.functionType(FunctionType(
            params: [types.anyType, types.anyType],
            returnType: types.anyType
        )))
        let foldReturnType: TypeID
        if let mapSymbol {
            foldReturnType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(kTypeParam), .invariant(types.anyType)],
                nullability: .nonNull
            )))
        } else {
            foldReturnType = types.anyType
        }
        registerGroupingMember(
            named: "fold",
            groupingFQName: groupingFQName,
            groupingSymbol: groupingSymbol,
            receiverType: groupingType,
            parameters: [
                (name: "initialValue", type: types.anyType),
                (name: "operation", type: foldOperationType),
            ],
            returnType: foldReturnType,
            externalLinkName: "kk_grouping_fold",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // reduce(operation: (S, T) -> S) -> Map<K, S>
        let reduceOperationType = types.make(.functionType(FunctionType(
            params: [types.anyType, types.anyType],
            returnType: types.anyType
        )))
        let reduceReturnType: TypeID
        if let mapSymbol {
            reduceReturnType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(kTypeParam), .invariant(types.anyType)],
                nullability: .nonNull
            )))
        } else {
            reduceReturnType = types.anyType
        }
        registerGroupingMember(
            named: "reduce",
            groupingFQName: groupingFQName,
            groupingSymbol: groupingSymbol,
            receiverType: groupingType,
            parameters: [
                (name: "operation", type: reduceOperationType),
            ],
            returnType: reduceReturnType,
            externalLinkName: "kk_grouping_reduce",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerGroupingMember(
        named name: String,
        groupingFQName: [InternedString],
        groupingSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = groupingFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(groupingSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType
            ),
            for: memberSymbol
        )
    }

    // MARK: - STDLIB-470: Sequence.toSet/toMap/groupBy/maxOrNull/minOrNull/flatten

    private func registerSyntheticSequenceTerminalMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinSequencesPkg: [InternedString]
    ) {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        // first(): T
        registerSequenceMemberStub(
            named: "first",
            externalLinkName: "kk_sequence_first",
            receiverType: receiverType,
            parameters: [],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // firstOrNull(): T?
        registerSequenceMemberStub(
            named: "firstOrNull",
            externalLinkName: "kk_sequence_firstOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // last(): T
        registerSequenceMemberStub(
            named: "last",
            externalLinkName: "kk_sequence_last",
            receiverType: receiverType,
            parameters: [],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // lastOrNull(): T?
        registerSequenceMemberStub(
            named: "lastOrNull",
            externalLinkName: "kk_sequence_lastOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // singleOrNull(): T?
        registerSequenceMemberStub(
            named: "singleOrNull",
            externalLinkName: "kk_sequence_singleOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // count(): Int
        registerSequenceMemberStub(
            named: "count",
            externalLinkName: "kk_sequence_count",
            receiverType: receiverType,
            parameters: [],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toSet(): Set<T>
        registerSequenceMemberStub(
            named: "toSet",
            externalLinkName: "kk_sequence_toSet",
            receiverType: receiverType,
            parameters: [],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toMap(): Map<K,V>
        registerSequenceMemberStub(
            named: "toMap",
            externalLinkName: "kk_sequence_toMap",
            receiverType: receiverType,
            parameters: [],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // groupBy(keySelector: (T) -> K): Map<K, List<T>>
        registerSequenceMemberStub(
            named: "groupBy",
            externalLinkName: "kk_sequence_groupBy",
            receiverType: receiverType,
            parameters: [("keySelector", types.anyType)],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // maxOrNull(): T?
        registerSequenceMemberStub(
            named: "maxOrNull",
            externalLinkName: "kk_sequence_maxOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(types.anyType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // minOrNull(): T?
        registerSequenceMemberStub(
            named: "minOrNull",
            externalLinkName: "kk_sequence_minOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(types.anyType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // flatten(): Sequence<T>
        registerSequenceMemberStub(
            named: "flatten",
            externalLinkName: "kk_sequence_flatten",
            receiverType: receiverType,
            parameters: [],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSequenceScopeMember(
        named name: String,
        sequenceScopeSymbol: SymbolID,
        sequenceScopeFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = sequenceScopeFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(sequenceScopeSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticDurationMember(
        named name: String,
        externalLinkName: String,
        durationSymbol: SymbolID,
        durationFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isProperty: Bool = false
    ) {
        let memberName = interner.intern(name)
        let memberFQName = durationFQName + [memberName]

        // If a symbol already exists at this fqName, ensure its linkage
        // metadata is up-to-date (mirroring registerSyntheticTopLevelFunction).
        if let existing = symbols.lookup(fqName: memberFQName) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if isProperty {
                symbols.setPropertyType(returnType, for: existing)
            }
            return
        }

        if isProperty {
            let memberSymbol = symbols.define(
                kind: .property,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(durationSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(returnType, for: memberSymbol)
        } else {
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(durationSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }
    }

    private func registerSequenceMemberStub(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        sequenceSymbol: SymbolID,
        sequenceFQName: [InternedString],
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = sequenceFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }
}
