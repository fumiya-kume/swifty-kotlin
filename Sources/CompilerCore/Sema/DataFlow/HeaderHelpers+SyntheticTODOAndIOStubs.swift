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
        let sequenceSymbol = registerSyntheticSequenceStub(
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

        registerSyntheticGenericSequenceVarargFunction(
            named: "sequenceOf",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_sequence_of",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-277: emptySequence<T>()
        registerSyntheticGenericSequenceNoArgFunction(
            named: "emptySequence",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_empty_sequence",
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticGenerateSequenceFunction(
            named: "generateSequence",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_sequence_generate",
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        registerSyntheticGenerateSequenceNoArgFunction(
            named: "generateSequence",
            packageFQName: kotlinSequencesPkg,
            sequenceSymbol: sequenceSymbol,
            externalLinkName: "kk_sequence_generate_noarg",
            symbols: symbols,
            types: types,
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

        registerSyntheticTopLevelFunction(
            named: "getTimeMicros",
            packageFQName: kotlinSystemPkg,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_system_getTimeMicros",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "getTimeMillis",
            packageFQName: kotlinSystemPkg,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_system_getTimeMillis",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "getTimeNanos",
            packageFQName: kotlinSystemPkg,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_system_getTimeNanos",
            symbols: symbols,
            interner: interner
        )

        let blockFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))

        registerSyntheticTopLevelFunction(
            named: "measureTimeMicros",
            packageFQName: kotlinSystemPkg,
            parameters: [(name: "block", type: blockFunctionType)],
            returnType: types.longType,
            externalLinkName: "kk_system_measureTimeMicros",
            symbols: symbols,
            interner: interner
        )

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
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "processStartNanos",
            externalLinkName: "kk_system_process_start_nanos",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.native.Platform (STDLIB-NATIVE-169) ---
        let kotlinNativePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("native")],
            symbols: symbols
        )
        let osFamilySymbol = ensureSyntheticPlatformEnumClass(
            named: "OsFamily",
            entries: [
                "UNKNOWN", "MACOSX", "IOS", "TVOS", "WATCHOS",
                "LINUX", "WINDOWS", "ANDROID", "WASM",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let osFamilyType = types.make(.classType(ClassType(
            classSymbol: osFamilySymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: osFamilySymbol,
            enumType: osFamilyType,
            symbols: symbols
        )

        let cpuArchitectureSymbol = ensureSyntheticPlatformEnumClass(
            named: "CpuArchitecture",
            entries: [
                "UNKNOWN", "X86", "X64", "ARM32",
                "ARM64", "MIPS32", "MIPSEL32", "WASM32",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let cpuArchitectureType = types.make(.classType(ClassType(
            classSymbol: cpuArchitectureSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: cpuArchitectureSymbol,
            enumType: cpuArchitectureType,
            symbols: symbols
        )
        let memoryModelSymbol = ensureSyntheticPlatformEnumClass(
            named: "MemoryModel",
            entries: [
                "STRICT", "RELAXED", "EXPERIMENTAL",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let memoryModelType = types.make(.classType(ClassType(
            classSymbol: memoryModelSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: memoryModelSymbol,
            enumType: memoryModelType,
            symbols: symbols
        )

        let platformSymbol = ensureSyntheticObjectSymbol(
            named: "Platform",
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let platformType = types.make(.classType(ClassType(
            classSymbol: platformSymbol,
            args: [],
            nullability: .nonNull
        )))
        let booleanType = types.make(.primitive(.boolean, .nonNull))
        symbols.setPropertyType(platformType, for: platformSymbol)

        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "canAccessUnaligned",
            propertyType: booleanType,
            externalLinkName: "kk_platform_canAccessUnaligned",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "isLittleEndian",
            propertyType: booleanType,
            externalLinkName: "kk_platform_isLittleEndian",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "osFamily",
            propertyType: osFamilyType,
            externalLinkName: "kk_platform_osFamily",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "cpuArchitecture",
            propertyType: cpuArchitectureType,
            externalLinkName: "kk_platform_cpuArchitecture",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "memoryModel",
            propertyType: memoryModelType,
            externalLinkName: "kk_platform_memoryModel",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: platformSymbol,
            ownerType: platformType,
            name: "getAvailableProcessors",
            externalLinkName: "kk_platform_getAvailableProcessors",
            returnType: types.intType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- java.lang.System / Runtime memory management (STDLIB-PERF-154) ---
        let javaLangPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("java"), interner.intern("lang")],
            symbols: symbols
        )

        let javaSystemSymbol = ensureSyntheticObjectSymbol(
            named: "System",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let javaSystemType = types.make(.classType(ClassType(
            classSymbol: javaSystemSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaSystemType, for: javaSystemSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: javaSystemSymbol,
            ownerType: javaSystemType,
            name: "gc",
            externalLinkName: "kk_system_gc",
            returnType: types.unitType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        let runtimeSymbol = ensureSyntheticObjectSymbol(
            named: "Runtime",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let runtimeType = types.make(.classType(ClassType(
            classSymbol: runtimeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(runtimeType, for: runtimeSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "getRuntime",
            externalLinkName: "kk_runtime_getRuntime",
            returnType: runtimeType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "totalMemory",
            externalLinkName: "kk_runtime_totalMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "freeMemory",
            externalLinkName: "kk_runtime_freeMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "maxMemory",
            externalLinkName: "kk_runtime_maxMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.synchronized (STDLIB-325) ---
        let synchronizedBlockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.makeNullable(types.anyType)
        )))
        registerSyntheticTopLevelFunction(
            named: "synchronized",
            packageFQName: kotlinPkg,
            parameters: [
                (name: "lock", type: types.anyType),
                (name: "block", type: synchronizedBlockType),
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

        let deprecatedCreateTempDirAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Avoid creating temporary directories in the default temp location with this function due to too wide permissions on the newly created directory. Use kotlin.io.path.createTempDirectory instead.\"",
                    "replaceWith = ReplaceWith(\"kotlin.io.path.createTempDirectory(prefix)\")",
                    "level = DeprecationLevel.ERROR",
                ]
            ),
        ]
        let deprecatedCreateTempFileAnnotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Avoid creating temporary files in the default temp location with this function due to too wide permissions on the newly created file. Use kotlin.io.path.createTempFile instead or resort to java.io.File.createTempFile.\"",
                    "replaceWith = ReplaceWith(\"kotlin.io.path.createTempFile(prefix, suffix)\")",
                    "level = DeprecationLevel.ERROR",
                ]
            ),
        ]

        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir_default",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "prefix", type: types.stringType)],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir_prefix",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir_prefix_suffix",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempDir",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
                (name: "directory", type: types.makeNullable(fileType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempDir",
            annotations: deprecatedCreateTempDirAnnotations,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile_default",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [(name: "prefix", type: types.stringType)],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile_prefix",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile_prefix_suffix",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPkg,
            parameters: [
                (name: "prefix", type: types.stringType),
                (name: "suffix", type: types.makeNullable(types.stringType)),
                (name: "directory", type: types.makeNullable(fileType)),
            ],
            returnType: fileType,
            externalLinkName: "kk_io_createTempFile",
            annotations: deprecatedCreateTempFileAnnotations,
            symbols: symbols,
            interner: interner
        )

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

        // --- STDLIB-HOF-029: 関数型完全実装 ---
        registerSyntheticFunctionTypes(
            symbols: symbols,
            types: types,
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

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func ensureSyntheticPlatformEnumClass(
        named name: String,
        entries: [String],
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            enumSymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
                symbols.setParentSymbol(pkgSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func setSyntheticPlatformEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else {
                continue
            }
            symbols.setPropertyType(enumType, for: child)
        }
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

    private func registerSyntheticGenericSequenceVarargFunction(
        named name: String,
        packageFQName: [InternedString],
        sequenceSymbol: SymbolID,
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

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

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
                parameterTypes: [elementType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticGenericSequenceNoArgFunction(
        named name: String,
        packageFQName: [InternedString],
        sequenceSymbol: SymbolID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes.isEmpty
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

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticGenerateSequenceFunction(
        named name: String,
        packageFQName: [InternedString],
        sequenceSymbol: SymbolID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes.count == 2
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

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let nullableElementType = types.makeNullable(elementType)
        let nextFunctionType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: nullableElementType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        let seedName = interner.intern("seed")
        let nextFunctionName = interner.intern("nextFunction")
        let seedSymbol = symbols.define(
            kind: .valueParameter,
            name: seedName,
            fqName: functionFQName + [seedName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let nextFunctionSymbol = symbols.define(
            kind: .valueParameter,
            name: nextFunctionName,
            fqName: functionFQName + [nextFunctionName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: seedSymbol)
        symbols.setParentSymbol(functionSymbol, for: nextFunctionSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [elementType, nextFunctionType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [seedSymbol, nextFunctionSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false],
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    /// STDLIB-SEQ-002: Register the 1-arg overload `generateSequence(nextFunction: () -> T?)`.
    /// This overload takes a no-argument function that is called repeatedly until it returns null.
    private func registerSyntheticGenerateSequenceNoArgFunction(
        named name: String,
        packageFQName: [InternedString],
        sequenceSymbol: SymbolID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        // Skip if an overload with exactly 1 parameter already exists.
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes.count == 1
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

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)

        let elementType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let nullableElementType = types.makeNullable(elementType)
        // The no-arg nextFunction type: () -> T?
        let nextFunctionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: nullableElementType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        let nextFunctionName = interner.intern("nextFunction")
        let nextFunctionSymbol = symbols.define(
            kind: .valueParameter,
            name: nextFunctionName,
            fqName: functionFQName + [nextFunctionName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: nextFunctionSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [nextFunctionType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [nextFunctionSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol]
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
        annotations: [MetadataAnnotationRecord] = [],
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
            if !annotations.isEmpty {
                symbols.setAnnotations(annotations, for: existing)
            }
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
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: functionSymbol)
        }

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

        let chunkedName = interner.intern("chunked")
        let chunkedFQName = sequenceFQName + [chunkedName]
        if let listSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]) {
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let chunkType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(typeParamType)],
                nullability: .nonNull
            )))
            let transformType = types.make(.functionType(FunctionType(
                params: [chunkType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let returnType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(types.anyType)],
                nullability: .nonNull
            )))
            let alreadyRegistered = symbols.lookupAll(fqName: chunkedFQName).contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes.count == 2
                    && symbols.externalLinkName(for: symID) == "kk_sequence_chunked_transform"
            }
            if !alreadyRegistered {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: chunkedName,
                    fqName: chunkedFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_sequence_chunked_transform", for: memberSymbol)
                let receiverType = types.make(.classType(ClassType(
                    classSymbol: sequenceSymbol,
                    args: [.out(typeParamType)],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType, transformType],
                        returnType: returnType,
                        typeParameterSymbols: [typeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
        }

        let sequenceElementType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let nullableReceiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(sequenceElementType)],
            nullability: .nullable
        )))
        let nonNullReceiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(sequenceElementType)],
            nullability: .nonNull
        )))
        registerSyntheticSequenceExtensionFunction(
            named: "orEmpty",
            externalLinkName: "kk_sequence_orEmpty",
            receiverType: nullableReceiverType,
            parameters: [],
            returnType: nonNullReceiverType,
            typeParameterSymbols: [typeParamSymbol],
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        return sequenceSymbol
    }

    private func registerSyntheticSequenceExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameters.map { $0.type }
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

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
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

        let tTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol)))
        let kTypeParam = types.make(.typeParam(TypeParamType(symbol: kParamSymbol)))

        let groupingType = types.make(.classType(ClassType(
            classSymbol: groupingSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Build Map<K, V> return types when Map symbol is available.
        let mapName = interner.intern("Map")
        let mutableMapName = interner.intern("MutableMap")
        let mapSymbol = symbols.lookup(fqName: collectionsPkg + [mapName])
            ?? symbols.lookupByShortName(mapName).first
        let mutableMapSymbol = symbols.lookup(fqName: collectionsPkg + [mutableMapName])
            ?? symbols.lookupByShortName(mutableMapName).first

        let groupingTypeParameterSymbols: [SymbolID] = [tParamSymbol, kParamSymbol]

        func makeMapType(valueType: TypeID) -> TypeID {
            guard let mapSymbol else {
                return types.anyType
            }
            return types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(kTypeParam), .invariant(valueType)],
                nullability: .nonNull
            )))
        }

        func registerGroupingMember(
            named name: String,
            parameters: [TypeID],
            returnType: TypeID,
            externalLinkName: String,
            typeParameterSymbols: [SymbolID] = groupingTypeParameterSymbols,
            classTypeParameterCount: Int = 2
        ) {
            let memberName = interner.intern(name)
            let memberFQName = groupingFQName + [memberName]
            let memberSignature = FunctionSignature(
                receiverType: groupingType,
                parameterTypes: parameters,
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            )
            if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                symbols.functionSignature(for: symbolID) == memberSignature
            }) {
                if symbols.externalLinkName(for: existing) != externalLinkName {
                    symbols.setExternalLinkName(externalLinkName, for: existing)
                }
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
            symbols.setParentSymbol(groupingSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(memberSignature, for: memberSymbol)
        }

        // eachCount() -> Map<K, Int>
        registerGroupingMember(
            named: "eachCount",
            parameters: [],
            returnType: makeMapType(valueType: types.intType),
            externalLinkName: "kk_grouping_eachCount"
        )

        // aggregate(operation: (K, R?, T, Boolean) -> R) -> Map<K, R>
        let aggregateRName = interner.intern("AggregateR")
        let aggregateRFQName = groupingFQName + [interner.intern("aggregate"), aggregateRName]
        let aggregateRSymbol: SymbolID = if let existing = symbols.lookup(fqName: aggregateRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: aggregateRName,
                fqName: aggregateRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let aggregateRType = types.make(.typeParam(TypeParamType(symbol: aggregateRSymbol)))
        let aggregateOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, types.makeNullable(aggregateRType), tTypeParam, types.booleanType],
            returnType: aggregateRType
        )))
        registerGroupingMember(
            named: "aggregate",
            parameters: [
                aggregateOperationType,
            ],
            returnType: makeMapType(valueType: aggregateRType),
            externalLinkName: "kk_grouping_aggregate",
            typeParameterSymbols: groupingTypeParameterSymbols + [aggregateRSymbol]
        )

        // aggregateTo(destination, operation) -> destination
        let aggregateToRName = interner.intern("AggregateToR")
        let aggregateToRFQName = groupingFQName + [interner.intern("aggregateTo"), aggregateToRName]
        let aggregateToRSymbol: SymbolID = if let existing = symbols.lookup(fqName: aggregateToRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: aggregateToRName,
                fqName: aggregateToRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let aggregateToRType = types.make(.typeParam(TypeParamType(symbol: aggregateToRSymbol)))
        let aggregateToDestinationType: TypeID
        if let mutableMapSymbol {
            aggregateToDestinationType = types.make(.classType(ClassType(
                classSymbol: mutableMapSymbol,
                args: [.invariant(kTypeParam), .invariant(aggregateToRType)],
                nullability: .nonNull
            )))
        } else {
            aggregateToDestinationType = types.anyType
        }
        let aggregateToOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, types.makeNullable(aggregateToRType), tTypeParam, types.booleanType],
            returnType: aggregateToRType
        )))
        registerGroupingMember(
            named: "aggregateTo",
            parameters: [
                aggregateToDestinationType,
                aggregateToOperationType,
            ],
            returnType: aggregateToDestinationType,
            externalLinkName: "kk_grouping_aggregateTo",
            typeParameterSymbols: groupingTypeParameterSymbols + [aggregateToRSymbol]
        )

        // eachCountTo(destination: MutableMap<in K, Int>) -> MutableMap<in K, Int>
        let eachCountToDestinationType: TypeID
        if let mutableMapSymbol {
            eachCountToDestinationType = types.make(.classType(ClassType(
                classSymbol: mutableMapSymbol,
                args: [.in(kTypeParam), .invariant(types.intType)],
                nullability: .nonNull
            )))
        } else {
            eachCountToDestinationType = types.anyType
        }
        registerGroupingMember(
            named: "eachCountTo",
            parameters: [
                eachCountToDestinationType,
            ],
            returnType: eachCountToDestinationType,
            externalLinkName: "kk_grouping_eachCountTo"
        )

        // fold(initialValue: R, operation: (R, T) -> R) -> Map<K, R>
        let foldRName = interner.intern("R")
        let foldRFQName = groupingFQName + [foldRName]
        let foldRSymbol: SymbolID = if let existing = symbols.lookup(fqName: foldRFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: foldRName,
                fqName: foldRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let foldRType = types.make(.typeParam(TypeParamType(symbol: foldRSymbol)))
        let foldOperationType = types.make(.functionType(FunctionType(
            params: [foldRType, tTypeParam],
            returnType: foldRType
        )))
        registerGroupingMember(
            named: "fold",
            parameters: [
                foldRType,
                foldOperationType,
            ],
            returnType: makeMapType(valueType: foldRType),
            externalLinkName: "kk_grouping_fold",
            typeParameterSymbols: groupingTypeParameterSymbols + [foldRSymbol]
        )

        // fold(initialValueSelector: (K, T) -> R, operation: (K, R, T) -> R) -> Map<K, R>
        let foldInitialValueSelectorType = types.make(.functionType(FunctionType(
            params: [kTypeParam, tTypeParam],
            returnType: foldRType
        )))
        let foldWithSelectorOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, foldRType, tTypeParam],
            returnType: foldRType
        )))
        registerGroupingMember(
            named: "fold",
            parameters: [
                foldInitialValueSelectorType,
                foldWithSelectorOperationType,
            ],
            returnType: makeMapType(valueType: foldRType),
            externalLinkName: "kk_grouping_fold_initialValueSelector",
            typeParameterSymbols: groupingTypeParameterSymbols + [foldRSymbol]
        )

        // foldTo(destination, initialValue, operation) -> destination
        let foldToOperationType = types.make(.functionType(FunctionType(
            params: [types.anyType, tTypeParam],
            returnType: types.anyType
        )))
        registerGroupingMember(
            named: "foldTo",
            parameters: [
                types.anyType,
                types.anyType,
                foldToOperationType,
            ],
            returnType: types.anyType,
            externalLinkName: "kk_grouping_foldTo"
        )

        // foldTo(destination, initialValueSelector, operation) -> destination
        let foldToInitialValueSelectorType = types.make(.functionType(FunctionType(
            params: [kTypeParam, tTypeParam],
            returnType: types.anyType
        )))
        let foldToKeyedOperationType = types.make(.functionType(FunctionType(
            params: [kTypeParam, types.anyType, tTypeParam],
            returnType: types.anyType
        )))
        registerGroupingMember(
            named: "foldTo",
            parameters: [
                types.anyType,
                foldToInitialValueSelectorType,
                foldToKeyedOperationType,
            ],
            returnType: types.anyType,
            externalLinkName: "kk_grouping_foldTo_selector"
        )

        // reduce(operation: (S, T) -> S) -> Map<K, S>
        let reduceSName = interner.intern("S")
        let reduceSFQName = groupingFQName + [reduceSName]
        let reduceSSymbol: SymbolID = if let existing = symbols.lookup(fqName: reduceSFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: reduceSName,
                fqName: reduceSFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let reduceSType = types.make(.typeParam(TypeParamType(symbol: reduceSSymbol)))
        let reduceOperationType = types.make(.functionType(FunctionType(
            params: [reduceSType, tTypeParam],
            returnType: reduceSType
        )))
        registerGroupingMember(
            named: "reduce",
            parameters: [
                reduceOperationType,
            ],
            returnType: makeMapType(valueType: reduceSType),
            externalLinkName: "kk_grouping_reduce",
            typeParameterSymbols: groupingTypeParameterSymbols + [reduceSSymbol]
        )

        // reduceTo(destination, operation) -> destination
        let reduceToDestinationType: TypeID
        if let mapSymbol {
            reduceToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.out(types.anyType), .out(types.anyType)],
                nullability: .nonNull
            )))
        } else {
            reduceToDestinationType = types.anyType
        }
        let reduceToOperationType = types.make(.functionType(FunctionType(
            params: [types.anyType, types.anyType, types.anyType],
            returnType: types.anyType
        )))
        registerGroupingMember(
            named: "reduceTo",
            parameters: [
                reduceToDestinationType,
                reduceToOperationType,
            ],
            returnType: reduceToDestinationType,
            externalLinkName: "kk_grouping_reduceTo",
            typeParameterSymbols: groupingTypeParameterSymbols
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
        let predicateType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let foldIndexedOperationType = types.make(.functionType(FunctionType(
            params: [types.intType, types.anyType, typeParamType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let reduceIndexedOperationType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType, typeParamType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))
        func nominalCollectionType(_ fqName: [InternedString], elementType: TypeID, invariant: Bool = false) -> TypeID {
            guard let symbol = symbols.lookup(fqName: fqName) else {
                return types.anyType
            }
            return types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [invariant ? .invariant(elementType) : .out(elementType)],
                nullability: .nonNull
            )))
        }
        func registerSequenceOverloadedMemberStub(
            named name: String,
            externalLinkName: String,
            receiverType: TypeID,
            parameters: [(name: String, type: TypeID)],
            returnType: TypeID,
            additionalTypeParameterSymbols: [SymbolID] = [],
            additionalTypeParameterUpperBoundsList: [[TypeID]] = [],
            canThrow: Bool = false
        ) {
            let memberName = interner.intern(name)
            let memberFQName = sequenceFQName + [memberName]
            let parameterTypes = parameters.map { $0.type }
            let hasMatchingSignature = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return sig.receiverType == receiverType
                    && sig.parameterTypes == parameterTypes
                    && sig.returnType == returnType
            }
            guard !hasMatchingSignature else { return }

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
                parameterSymbols.append(parameterSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    canThrow: canThrow,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                    valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                    typeParameterSymbols: [typeParamSymbol] + additionalTypeParameterSymbols,
                    typeParameterUpperBoundsList: [[]] + additionalTypeParameterUpperBoundsList,
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
        let listReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ], elementType: typeParamType)
        let mutableListReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ], elementType: typeParamType, invariant: true)
        let collectionReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ], elementType: typeParamType)
        let setReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ], elementType: typeParamType)
        let mutableSetReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ], elementType: typeParamType, invariant: true)

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

        // firstNotNullOf<T, R>(transform: (T) -> R?): R
        // Use a method-local T parameter (independent of Sequence's `out T`)
        // so the projection on the receiver does not block referencing T in
        // the transform's `in` position.
        do {
            let memberName = interner.intern("firstNotNullOf")
            let methodTName = interner.intern("T")
            let methodTSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, methodTName]) ?? symbols.define(
                kind: .typeParameter,
                name: methodTName,
                fqName: sequenceFQName + [memberName, methodTName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let methodTType = types.make(.typeParam(TypeParamType(symbol: methodTSymbol, nullability: .nonNull)))
            let methodReceiverType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(methodTType)],
                nullability: .nonNull
            )))
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [memberName, rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let transformType = types.make(.functionType(FunctionType(
                params: [methodTType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "firstNotNullOf",
                externalLinkName: "kk_sequence_firstNotNullOf",
                receiverType: methodReceiverType,
                parameters: [("transform", transformType)],
                returnType: rType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // firstNotNullOfOrNull<T, R>(transform: (T) -> R?): R?
        do {
            let memberName = interner.intern("firstNotNullOfOrNull")
            let methodTName = interner.intern("T")
            let methodTSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, methodTName]) ?? symbols.define(
                kind: .typeParameter,
                name: methodTName,
                fqName: sequenceFQName + [memberName, methodTName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let methodTType = types.make(.typeParam(TypeParamType(symbol: methodTSymbol, nullability: .nonNull)))
            let methodReceiverType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(methodTType)],
                nullability: .nonNull
            )))
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [memberName, rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let transformType = types.make(.functionType(FunctionType(
                params: [methodTType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "firstNotNullOfOrNull",
                externalLinkName: "kk_sequence_firstNotNullOfOrNull",
                receiverType: methodReceiverType,
                parameters: [("transform", transformType)],
                returnType: types.makeNullable(rType),
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]],
                flags: [.synthetic, .inlineFunction]
            )
        }

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

        // fold(initial: R, operation: (R, T) -> R): R
        let foldName = interner.intern("fold")
        let foldFQName = sequenceFQName + [foldName]
        if symbols.lookup(fqName: foldFQName) == nil {
            let foldRName = interner.intern("R")
            let foldRSymbol = symbols.define(
                kind: .typeParameter,
                name: foldRName,
                fqName: foldFQName + [foldRName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let foldRType = types.make(.typeParam(TypeParamType(
                symbol: foldRSymbol,
                nullability: .nonNull
            )))
            let foldOperationType = types.make(.functionType(FunctionType(
                params: [foldRType, typeParamType],
                returnType: foldRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "fold",
                externalLinkName: "kk_sequence_fold",
                receiverType: receiverType,
                parameters: [
                    ("initial", foldRType),
                    ("operation", foldOperationType),
                ],
                returnType: foldRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [foldRSymbol]
            )
        }

        // contains(element: T): Boolean
        registerSequenceMemberStub(
            named: "contains",
            externalLinkName: "kk_sequence_contains",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // any(): Boolean
        registerSequenceMemberStub(
            named: "any",
            externalLinkName: "kk_sequence_any",
            receiverType: receiverType,
            parameters: [],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // indexOf(element: T): Int
        registerSequenceMemberStub(
            named: "indexOf",
            externalLinkName: "kk_sequence_indexOf",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // elementAtOrNull(index: Int): T?
        registerSequenceMemberStub(
            named: "elementAtOrNull",
            externalLinkName: "kk_sequence_elementAtOrNull",
            receiverType: receiverType,
            parameters: [("index", types.intType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // none(): Boolean
        registerSequenceMemberStub(
            named: "none",
            externalLinkName: "kk_sequence_none",
            receiverType: receiverType,
            parameters: [],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // elementAt(index: Int): T
        registerSequenceMemberStub(
            named: "elementAt",
            externalLinkName: "kk_sequence_elementAt",
            receiverType: receiverType,
            parameters: [("index", types.intType)],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // findLast(predicate: (T) -> Boolean): T?
        registerSequenceMemberStub(
            named: "findLast",
            externalLinkName: "kk_sequence_findLast",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // sum()/average()
        registerSequenceMemberStub(
            named: "sum",
            externalLinkName: "kk_sequence_sum",
            receiverType: receiverType,
            parameters: [],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSequenceMemberStub(
            named: "average",
            externalLinkName: "kk_sequence_average",
            receiverType: receiverType,
            parameters: [],
            returnType: types.doubleType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        let sequenceElementToIntType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "sumBy",
            externalLinkName: "kk_sequence_sumBy",
            receiverType: receiverType,
            parameters: [("selector", sequenceElementToIntType)],
            returnType: types.intType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use sumOf instead.\"",
                        "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                    ]
                ),
            ],
            canThrow: true
        )
        let sequenceElementToDoubleType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.doubleType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "sumByDouble",
            externalLinkName: "kk_sequence_sumByDouble",
            receiverType: receiverType,
            parameters: [("selector", sequenceElementToDoubleType)],
            returnType: types.doubleType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            annotations: [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use sumOf instead.\"",
                        "replaceWith = ReplaceWith(\"sumOf(selector)\")",
                    ]
                ),
            ],
            canThrow: true
        )

        // toList(): List<T>
        registerSequenceMemberStub(
            named: "toList",
            externalLinkName: "kk_sequence_to_list",
            receiverType: receiverType,
            parameters: [],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // STDLIB-SEQ-006: constrainOnce(): Sequence<T>
        registerSequenceMemberStub(
            named: "constrainOnce",
            externalLinkName: "kk_sequence_constrainOnce",
            receiverType: receiverType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toMutableList(): MutableList<T>
        registerSequenceMemberStub(
            named: "toMutableList",
            externalLinkName: "kk_sequence_toMutableList",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableListReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // asIterable(): Iterable<T>
        registerSequenceMemberStub(
            named: "asIterable",
            externalLinkName: "kk_sequence_asIterable",
            receiverType: receiverType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toMutableSet(): MutableSet<T>
        registerSequenceMemberStub(
            named: "toMutableSet",
            externalLinkName: "kk_sequence_toMutableSet",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableSetReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toHashSet(): MutableSet<T>
        registerSequenceMemberStub(
            named: "toHashSet",
            externalLinkName: "kk_sequence_toHashSet",
            receiverType: receiverType,
            parameters: [],
            returnType: mutableSetReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // toCollection(destination): Collection<T>
        registerSequenceMemberStub(
            named: "toCollection",
            externalLinkName: "kk_sequence_toCollection",
            receiverType: receiverType,
            parameters: [("destination", collectionReturnType)],
            returnType: collectionReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // filterNot(predicate): Sequence<T>
        registerSequenceMemberStub(
            named: "filterNot",
            externalLinkName: "kk_sequence_filterNot",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // flatMapIndexed(transform): Sequence<R> for Iterable<R> and Sequence<R> transform results.
        do {
            let memberName = interner.intern("flatMapIndexed")
            let memberFQName = sequenceFQName + [memberName]
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: memberFQName + [rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: memberFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            func registerFlatMapIndexedOverload(transformReturnType: TypeID) {
                let transformType = types.make(.functionType(FunctionType(
                    params: [types.intType, typeParamType],
                    returnType: transformReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == 1,
                          let parameterType = signature.parameterTypes.first
                    else { return false }
                    return parameterType == transformType
                }
                guard !alreadyRegistered else { return }

                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .operatorFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_sequence_flatMapIndexed", for: memberSymbol)

                let transformName = interner.intern("transform")
                let transformSymbol = symbols.define(
                    kind: .valueParameter,
                    name: transformName,
                    fqName: memberFQName + [transformName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: transformSymbol)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [transformType],
                        returnType: sequenceRType,
                        canThrow: true,
                        valueParameterSymbols: [transformSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: [typeParamSymbol, rSymbol],
                        typeParameterUpperBoundsList: [[], []],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            if let iterableSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]) {
                let iterableRType = types.make(.classType(ClassType(
                    classSymbol: iterableSymbol,
                    args: [.out(rType)],
                    nullability: .nonNull
                )))
                registerFlatMapIndexedOverload(transformReturnType: iterableRType)
            }
            registerFlatMapIndexedOverload(transformReturnType: sequenceRType)
        }

        // shuffled() / shuffled(random): Sequence<T> (STDLIB-SEQ-019)
        do {
            let shuffledName = interner.intern("shuffled")
            let shuffledFQName = sequenceFQName + [shuffledName]

            func registerShuffledOverload(
                parameters: [(name: String, type: TypeID)],
                externalLinkName: String
            ) {
                let alreadyRegistered = symbols.lookupAll(fqName: shuffledFQName).contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.parameterTypes.count == parameters.count
                        && symbols.externalLinkName(for: symbolID) == externalLinkName
                }
                guard !alreadyRegistered else { return }

                let memberSymbol = symbols.define(
                    kind: .function,
                    name: shuffledName,
                    fqName: shuffledFQName,
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
                        fqName: shuffledFQName + [parameterName],
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
                        returnType: receiverType,
                        valueParameterSymbols: parameterSymbols,
                        valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                        valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[]],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            registerShuffledOverload(parameters: [], externalLinkName: "kk_sequence_shuffled")

            if let randomSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("random"),
                interner.intern("Random"),
            ]) {
                let randomType = types.make(.classType(ClassType(
                    classSymbol: randomSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                registerShuffledOverload(
                    parameters: [("random", randomType)],
                    externalLinkName: "kk_sequence_shuffled_random"
                )
            }
        }

        // requireNoNulls(): Sequence<T> (STDLIB-SEQ-014)
        let nullableElementSequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(types.makeNullable(typeParamType))],
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "requireNoNulls",
            externalLinkName: "kk_sequence_requireNoNulls",
            receiverType: nullableElementSequenceType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> (STDLIB-SEQ-012)
        registerSequenceMemberStub(
            named: "partition",
            externalLinkName: "kk_sequence_partition",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )
        // plusElement(element: T): Sequence<T> (STDLIB-SEQ-013)
        registerSequenceMemberStub(
            named: "plusElement",
            externalLinkName: "kk_sequence_plus_element",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // minusElement(element: T): Sequence<T> (STDLIB-SEQ-028)
        registerSequenceMemberStub(
            named: "minusElement",
            externalLinkName: "kk_sequence_minus",
            receiverType: receiverType,
            parameters: [("element", typeParamType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // foldIndexed(initial, operation): R
        registerSequenceMemberStub(
            named: "foldIndexed",
            externalLinkName: "kk_sequence_foldIndexed",
            receiverType: receiverType,
            parameters: [("initial", types.anyType), ("operation", foldIndexedOperationType)],
            returnType: types.anyType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // reduceIndexed(operation): T
        registerSequenceMemberStub(
            named: "reduceIndexed",
            externalLinkName: "kk_sequence_reduceIndexed",
            receiverType: receiverType,
            parameters: [("operation", reduceIndexedOperationType)],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // reduceIndexedOrNull(operation): T?
        registerSequenceMemberStub(
            named: "reduceIndexedOrNull",
            externalLinkName: "kk_sequence_reduceIndexedOrNull",
            receiverType: receiverType,
            parameters: [("operation", reduceIndexedOperationType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // runningFoldIndexed(initial, operation): Sequence<R>
        let runningFoldIndexedName = interner.intern("runningFoldIndexed")
        let runningFoldIndexedFQName = sequenceFQName + [runningFoldIndexedName]
        if symbols.lookup(fqName: runningFoldIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: runningFoldIndexedFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(
                params: [types.intType, rType, typeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "runningFoldIndexed",
                externalLinkName: "kk_sequence_runningFoldIndexed",
                receiverType: receiverType,
                parameters: [("initial", rType), ("operation", operationType)],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]]
            )
        }

        // scanIndexed(initial, operation): Sequence<R>
        let scanIndexedName = interner.intern("scanIndexed")
        let scanIndexedFQName = sequenceFQName + [scanIndexedName]
        if symbols.lookup(fqName: scanIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: scanIndexedFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(
                params: [types.intType, rType, typeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "scanIndexed",
                externalLinkName: "kk_sequence_scanIndexed",
                receiverType: receiverType,
                parameters: [("initial", rType), ("operation", operationType)],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]]
            )
        }

        // runningReduceIndexed(operation): List<T>
        registerSequenceMemberStub(
            named: "runningReduceIndexed",
            externalLinkName: "kk_sequence_runningReduceIndexed",
            receiverType: receiverType,
            parameters: [("operation", reduceIndexedOperationType)],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // partition(predicate): Pair<List<T>, List<T>>
        if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")]) {
            let partitionReturnType = types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(listReturnType), .out(listReturnType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "partition",
                externalLinkName: "kk_sequence_partition",
                receiverType: receiverType,
                parameters: [("predicate", predicateType)],
                returnType: partitionReturnType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true
            )
        }

        // associateWith(valueSelector): Map<T, R>
        if let mapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]) {
            let associateWithFQName = sequenceFQName + [interner.intern("associateWith")]
            if symbols.lookup(fqName: associateWithFQName) == nil {
                let rName = interner.intern("R")
                let rFQName = associateWithFQName + [rName]
                let rSymbol = symbols.define(
                    kind: .typeParameter,
                    name: rName,
                    fqName: rFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
                let valueSelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: rType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: mapSymbol,
                    args: [.out(typeParamType), .out(rType)],
                    nullability: .nonNull
                )))
                let associateWithSymbol = symbols.define(
                    kind: .function,
                    name: interner.intern("associateWith"),
                    fqName: associateWithFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .operatorFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: associateWithSymbol)
                symbols.setExternalLinkName("kk_sequence_associateWith", for: associateWithSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [valueSelectorType],
                        returnType: returnType,
                        canThrow: true,
                        typeParameterSymbols: [typeParamSymbol, rSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: associateWithSymbol
                )
            }
        }

        if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")]),
           let mutableMapSymbol = symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("MutableMap"),
           ])
        {
            let associateToName = interner.intern("associateTo")
            let associateToFQName = sequenceFQName + [associateToName]
            if symbols.lookup(fqName: associateToFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: associateToFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let valueTypeParamName = interner.intern("V")
                let valueTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: valueTypeParamName,
                    fqName: associateToFQName + [valueTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(keyType), .out(valueType)],
                    nullability: .nonNull
                )))
                let transformType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(keyType), .out(valueType)],
                        nullability: .nonNull
                    ))),
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateTo",
                    externalLinkName: "kk_sequence_associateTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("transform", transformType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
                )
            }

            let associateByToName = interner.intern("associateByTo")
            let associateByToFQName = sequenceFQName + [associateByToName]
            if symbols.lookup(fqName: associateByToFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: associateByToFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(keyType), .out(typeParamType)],
                    nullability: .nonNull
                )))
                let keySelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateByTo",
                    externalLinkName: "kk_sequence_associateByTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("keySelector", keySelectorType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }

            let associateWithToName = interner.intern("associateWithTo")
            let associateWithToFQName = sequenceFQName + [associateWithToName]
            if symbols.lookup(fqName: associateWithToFQName) == nil {
                let valueTypeParamName = interner.intern("V")
                let valueTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: valueTypeParamName,
                    fqName: associateWithToFQName + [valueTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(typeParamType), .out(valueType)],
                    nullability: .nonNull
                )))
                let valueSelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: valueType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "associateWithTo",
                    externalLinkName: "kk_sequence_associateWithTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("valueSelector", valueSelectorType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [valueTypeParamSymbol]
                )
            }
        }

        if let mutableMapSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]) {
            let groupByToName = interner.intern("groupByTo")
            let groupByToFQName = sequenceFQName + [groupByToName]
            if symbols.lookup(fqName: groupByToFQName) == nil {
                let keyTypeParamName = interner.intern("K")
                let keyTypeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: keyTypeParamName,
                    fqName: groupByToFQName + [keyTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
                let destinationType = types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.out(keyType), .out(mutableListReturnType)],
                    nullability: .nonNull
                )))
                let keySelectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: "groupByTo",
                    externalLinkName: "kk_sequence_groupByTo",
                    receiverType: receiverType,
                    parameters: [("destination", destinationType), ("keySelector", keySelectorType)],
                    returnType: destinationType,
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: [keyTypeParamSymbol]
                )
            }
        }

        // maxByOrNull / minByOrNull / maxOf / minOf (STDLIB-301)
        do {
            func registerComparableSelectorMember(
                name: String,
                externalLinkName: String,
                returnTypeBuilder: (TypeID) -> TypeID
            ) {
                let memberName = interner.intern(name)
                let memberFQName = sequenceFQName + [memberName]
                guard symbols.lookup(fqName: memberFQName) == nil else { return }
                let selectorReturnType: TypeID
                let extraTypeParamSymbols: [SymbolID]
                let extraUpperBoundsList: [[TypeID]]
                if let rParam = makeComparableTypeParam(
                    symbols: symbols, types: types, interner: interner,
                    memberFQName: memberFQName
                ) {
                    selectorReturnType = rParam.type
                    extraTypeParamSymbols = [rParam.symbol]
                    extraUpperBoundsList = [rParam.upperBounds]
                } else {
                    selectorReturnType = types.anyType
                    extraTypeParamSymbols = []
                    extraUpperBoundsList = []
                }
                let selectorType = types.make(.functionType(FunctionType(
                    params: [typeParamType],
                    returnType: selectorReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                registerSequenceMemberStub(
                    named: name,
                    externalLinkName: externalLinkName,
                    receiverType: receiverType,
                    parameters: [("selector", selectorType)],
                    returnType: returnTypeBuilder(selectorReturnType),
                    sequenceSymbol: sequenceSymbol,
                    sequenceFQName: sequenceFQName,
                    typeParamSymbol: typeParamSymbol,
                    symbols: symbols,
                    interner: interner,
                    canThrow: true,
                    additionalTypeParameterSymbols: extraTypeParamSymbols,
                    additionalTypeParameterUpperBoundsList: extraUpperBoundsList
                )
            }

            registerComparableSelectorMember(
                name: "maxByOrNull",
                externalLinkName: "kk_sequence_maxByOrNull",
                returnTypeBuilder: { _ in types.makeNullable(typeParamType) }
            )
            registerComparableSelectorMember(
                name: "minByOrNull",
                externalLinkName: "kk_sequence_minByOrNull",
                returnTypeBuilder: { _ in types.makeNullable(typeParamType) }
            )
            registerComparableSelectorMember(
                name: "maxOf",
                externalLinkName: "kk_sequence_maxOf",
                returnTypeBuilder: { selectorResultType in selectorResultType }
            )
            registerComparableSelectorMember(
                name: "minOf",
                externalLinkName: "kk_sequence_minOf",
                returnTypeBuilder: { selectorResultType in selectorResultType }
            )
        }

        // unzip(): Pair<List<A>, List<B>> for Sequence<Pair<A, B>>
        let unzipName = interner.intern("unzip")
        let unzipFQName = sequenceFQName + [unzipName]
        if symbols.lookup(fqName: unzipFQName) == nil {
            let aName = interner.intern("A")
            let aSymbol = symbols.define(
                kind: .typeParameter,
                name: aName,
                fqName: unzipFQName + [aName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let bName = interner.intern("B")
            let bSymbol = symbols.define(
                kind: .typeParameter,
                name: bName,
                fqName: unzipFQName + [bName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let aType = types.make(.typeParam(TypeParamType(symbol: aSymbol, nullability: .nonNull)))
            let bType = types.make(.typeParam(TypeParamType(symbol: bSymbol, nullability: .nonNull)))
            let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
                ?? symbols.lookupByShortName(interner.intern("Pair")).first
            let specializedReceiverType: TypeID
            let returnType: TypeID
            if let pairSymbol {
                let pairElementType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(aType), .out(bType)],
                    nullability: .nonNull
                )))
                specializedReceiverType = types.make(.classType(ClassType(
                    classSymbol: sequenceSymbol,
                    args: [.out(pairElementType)],
                    nullability: .nonNull
                )))
                let firstListType = nominalCollectionType([
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ], elementType: aType)
                let secondListType = nominalCollectionType([
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ], elementType: bType)
                returnType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(firstListType), .out(secondListType)],
                    nullability: .nonNull
                )))
            } else {
                specializedReceiverType = receiverType
                returnType = types.anyType
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: unzipName,
                fqName: unzipFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_sequence_unzip", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: specializedReceiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [aSymbol, bSymbol],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

        // toSet(): Set<T>
        registerSequenceMemberStub(
            named: "toSet",
            externalLinkName: "kk_sequence_toSet",
            receiverType: receiverType,
            parameters: [],
            returnType: setReturnType,
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

        // STDLIB-SEQ-008: chunked(size, transform): Sequence<R>
        do {
            let chunkedName = interner.intern("chunked")
            let chunkedFQName = sequenceFQName + [chunkedName]
            let rName = interner.intern("R")
            let rFQName = chunkedFQName + [rName]
            let rSymbol: SymbolID = if let existing = symbols.lookup(fqName: rFQName) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: rName,
                    fqName: rFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            let rType = types.make(.typeParam(TypeParamType(
                symbol: rSymbol,
                nullability: .nonNull
            )))
            let invariantChunkListType = nominalCollectionType([
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ], elementType: typeParamType, invariant: true)
            let transformType = types.make(.functionType(FunctionType(
                params: [invariantChunkListType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceRType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "chunked",
                externalLinkName: "kk_sequence_chunked_transform",
                receiverType: receiverType,
                parameters: [("size", types.intType), ("transform", transformType)],
                returnType: sequenceRType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: typeParamSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol]
            )
        }

        // forEachIndexed(action: (Int, T) -> Unit): Unit
        let forEachIndexedActionType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceMemberStub(
            named: "forEachIndexed",
            externalLinkName: "kk_sequence_forEachIndexed",
            receiverType: receiverType,
            parameters: [("action", forEachIndexedActionType)],
            returnType: types.unitType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // onEachIndexed(action: (Int, T) -> Unit): Sequence<T>
        registerSequenceMemberStub(
            named: "onEachIndexed",
            externalLinkName: "kk_sequence_onEachIndexed",
            receiverType: receiverType,
            parameters: [("action", forEachIndexedActionType)],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // flatMapIndexed(transform: (Int, T) -> Iterable<R>): Sequence<R>
        // flatMapIndexed(transform: (Int, T) -> Sequence<R>): Sequence<R>
        let flatMapIndexedName = interner.intern("flatMapIndexed")
        let flatMapIndexedFQName = sequenceFQName + [flatMapIndexedName]
        let flatMapIndexedTypeParamName = interner.intern("R")
        let flatMapIndexedTypeParamSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: flatMapIndexedFQName + [flatMapIndexedTypeParamName]
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: flatMapIndexedTypeParamName,
                fqName: flatMapIndexedFQName + [flatMapIndexedTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let flatMapIndexedTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapIndexedTypeParamSymbol,
            nullability: .nonNull
        )))
        let iterableFlatMapIndexedReturnType = makeSyntheticIterableType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: flatMapIndexedTypeParamType
        )
        let sequenceFlatMapIndexedReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(flatMapIndexedTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapIndexedIterableTransformType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType],
            returnType: iterableFlatMapIndexedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let flatMapIndexedSequenceTransformType = types.make(.functionType(FunctionType(
            params: [types.intType, typeParamType],
            returnType: sequenceFlatMapIndexedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSequenceOverloadedMemberStub(
            named: "flatMapIndexed",
            externalLinkName: "kk_sequence_flatMapIndexed",
            receiverType: receiverType,
            parameters: [("transform", flatMapIndexedIterableTransformType)],
            returnType: sequenceFlatMapIndexedReturnType,
            additionalTypeParameterSymbols: [flatMapIndexedTypeParamSymbol]
        )
        registerSequenceOverloadedMemberStub(
            named: "flatMapIndexed",
            externalLinkName: "kk_sequence_flatMapIndexed",
            receiverType: receiverType,
            parameters: [("transform", flatMapIndexedSequenceTransformType)],
            returnType: sequenceFlatMapIndexedReturnType,
            additionalTypeParameterSymbols: [flatMapIndexedTypeParamSymbol]
        )

        // any(predicate: (T) -> Boolean): Boolean  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "any",
            externalLinkName: "kk_sequence_any",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // all(predicate: (T) -> Boolean): Boolean  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "all",
            externalLinkName: "kk_sequence_all",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // none(predicate: (T) -> Boolean): Boolean  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "none",
            externalLinkName: "kk_sequence_none",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.booleanType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // find(predicate: (T) -> Boolean): T?  (STDLIB-SEQ-007)
        registerSequenceMemberStub(
            named: "find",
            externalLinkName: "kk_sequence_find",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // zipWithNext(): List<Pair<T, T>>
        let zipWithNextName = interner.intern("zipWithNext")
        let zipWithNextFQName = sequenceFQName + [zipWithNextName]
        if symbols.lookup(fqName: zipWithNextFQName) == nil {
            let pairSymbol: SymbolID? = symbols.lookup(fqName: [
                interner.intern("kotlin"), interner.intern("Pair"),
            ])
            let zipWithNextResultType: TypeID = if let pairSymbol {
                types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(typeParamType), .out(typeParamType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            let listSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ])
            let zipWithNextListResultType: TypeID = if let listSymbol {
                types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(zipWithNextResultType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            let zipWithNextSymbol = symbols.define(
                kind: .function,
                name: zipWithNextName,
                fqName: zipWithNextFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(sequenceSymbol, for: zipWithNextSymbol)
            symbols.setExternalLinkName("kk_sequence_zipWithNext", for: zipWithNextSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: zipWithNextListResultType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: zipWithNextSymbol
            )
        }

        // zipWithNext(transform: (T, T) -> R): List<R>
        let zipWithNextTransformFQName = zipWithNextFQName + [interner.intern("transform")]
        if symbols.lookup(fqName: zipWithNextTransformFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = zipWithNextTransformFQName + [rName]
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let listSymbol = symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ])
            let listRType: TypeID = if let listSymbol {
                types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(rType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            let transformType = types.make(.functionType(FunctionType(
                params: [typeParamType, typeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let transformSymbol = symbols.define(
                kind: .function,
                name: zipWithNextName,
                fqName: zipWithNextTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(sequenceSymbol, for: transformSymbol)
            symbols.setExternalLinkName("kk_sequence_zipWithNextTransform", for: transformSymbol)
            let transformParamName = interner.intern("transform")
            let transformParamSymbol = symbols.define(
                kind: .valueParameter,
                name: transformParamName,
                fqName: zipWithNextTransformFQName + [transformParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(transformSymbol, for: transformParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: listRType,
                    valueParameterSymbols: [transformParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol, rSymbol],
                    classTypeParameterCount: 1
                ),
                for: transformSymbol
            )
        }
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
        interner: StringInterner,
        annotations: [MetadataAnnotationRecord] = [],
        canThrow: Bool = false,
        additionalTypeParameterSymbols: [SymbolID] = [],
        additionalTypeParameterUpperBoundsList: [[TypeID]] = [],
        flags: SymbolFlags = [.synthetic, .operatorFunction]
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
            flags: flags
        )
        symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: memberSymbol)
        }

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
                canThrow: canThrow,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: [typeParamSymbol] + additionalTypeParameterSymbols,
                typeParameterUpperBoundsList: [[]] + additionalTypeParameterUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticFunctionTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin.Function パッケージ階層の確立
        let kotlinFunctionPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("Function")],
            symbols: symbols
        )

        // Function0-22 のインターフェースを登録
        for arity in 0...22 {
            registerSyntheticFunctionInterface(
                arity: arity,
                packageFQName: kotlinFunctionPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        // 関数型の合成とカリー化拡張関数を登録
        registerSyntheticFunctionCompositionExtensions(
            packageFQName: kotlinFunctionPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticFunctionInterface(
        arity: Int,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let interfaceName = interner.intern("Function\(arity)")
        let interfaceFQName = packageFQName + [interfaceName]

        // 既に存在する場合はスキップ
        if symbols.lookup(fqName: interfaceFQName) != nil {
            return
        }

        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: interfaceName,
            fqName: interfaceFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // 型パラメータの定義
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []

        // 戻り値型パラメータ R (out変位)
        let returnParamName = interner.intern("R")
        let returnParamFQName = interfaceFQName + [returnParamName]
        let returnParamSymbol = symbols.define(
            kind: .typeParameter,
            name: returnParamName,
            fqName: returnParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        typeParamSymbols.append(returnParamSymbol)
        typeParamTypes.append(types.make(.typeParam(TypeParamType(
            symbol: returnParamSymbol,
            nullability: .nonNull
        ))))

        // パラメータ型 P1-P22 (in変位)
        if arity > 0 {
            for i in 1...arity {
                let paramName = interner.intern("P\(i)")
                let paramFQName = interfaceFQName + [paramName]
                let paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                typeParamSymbols.append(paramSymbol)
                typeParamTypes.append(types.make(.typeParam(TypeParamType(
                    symbol: paramSymbol,
                    nullability: .nonNull
                ))))
            }
        }

        // 型パラメータの変位指定を設定
        var variances: [TypeVariance] = [.out] // 戻り値はout
        if arity > 0 {
            for _ in 1...arity {
                variances.append(.in) // パラメータはin
            }
        }
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: interfaceSymbol)
        types.setNominalTypeParameterVariances(variances, for: interfaceSymbol)

        // invokeメソッドの登録
        registerSyntheticFunctionInvokeMethod(
            ownerSymbol: interfaceSymbol,
            arity: arity,
            typeParamSymbols: typeParamSymbols,
            interfaceFQName: interfaceFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticFunctionInvokeMethod(
        ownerSymbol: SymbolID,
        arity: Int,
        typeParamSymbols: [SymbolID],
        interfaceFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let invokeName = interner.intern("invoke")
        let invokeFQName = interfaceFQName + [invokeName]

        let invokeSymbol = symbols.define(
            kind: .function,
            name: invokeName,
            fqName: invokeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(ownerSymbol, for: invokeSymbol)
        symbols.setExternalLinkName("kk_function_invoke", for: invokeSymbol)

        // パラメータ型の構築
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []

        if arity > 0 {
            for i in 1...arity {
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbols[i],
                    nullability: .nonNull
                )))
                parameterTypes.append(paramType)

                let paramName = interner.intern("p\(i)")
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: invokeFQName + [paramName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(invokeSymbol, for: paramSymbol)
                parameterSymbols.append(paramSymbol)
            }
        }

        let returnType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbols[0], // R
            nullability: .nonNull
        )))

        // レシーバ型の構築
        let receiverType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: typeParamSymbols.enumerated().map { index, symbol in
                let variance: TypeVariance = index == 0 ? .out : .in
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: symbol,
                    nullability: .nonNull
                )))
                switch variance {
                case .out: return .out(paramType)
                case .in: return .in(paramType)
                case .invariant: return .invariant(paramType)
                }
            },
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: arity),
                valueParameterIsVararg: Array(repeating: false, count: arity),
                typeParameterSymbols: typeParamSymbols,
                classTypeParameterCount: typeParamSymbols.count
            ),
            for: invokeSymbol
        )
    }

    private func registerSyntheticFunctionCompositionExtensions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Function1.andThen 拡張関数
        registerSyntheticFunctionAndThenExtension(
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Function1.compose 拡張関数
        registerSyntheticFunctionComposeExtension(
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Function2.curried 拡張関数
        registerSyntheticFunctionCurriedExtension(
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticFunctionAndThenExtension(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let function1Name = interner.intern("Function1")
        let function1FQName = packageFQName + [function1Name]
        guard let function1Symbol = symbols.lookup(fqName: function1FQName) else { return }

        let andThenName = interner.intern("andThen")
        let andThenFQName = function1FQName + [andThenName]

        let andThenSymbol = symbols.define(
            kind: .function,
            name: andThenName,
            fqName: andThenFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(function1Symbol, for: andThenSymbol)
        symbols.setExternalLinkName("kk_function_andThen", for: andThenSymbol)

        // 型パラメータの定義
        let tParamName = interner.intern("T")
        let rParamName = interner.intern("R")
        let newRParamName = interner.intern("NewR")

        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: andThenFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rParamSymbol = symbols.define(
            kind: .typeParameter,
            name: rParamName,
            fqName: andThenFQName + [rParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let newRParamSymbol = symbols.define(
            kind: .typeParameter,
            name: newRParamName,
            fqName: andThenFQName + [newRParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )

        // パラメータ: g: (R) -> NewR
        let gFunctionType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: newRParamSymbol, nullability: .nonNull)))
        )))

        let gParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("g"),
            fqName: andThenFQName + [interner.intern("g")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(andThenSymbol, for: gParamSymbol)

        // 戻り値型: (T) -> NewR
        let returnType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: newRParamSymbol, nullability: .nonNull)))
        )))

        // レシーバ型: (T) -> R
        let receiverType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [gFunctionType],
                returnType: returnType,
                valueParameterSymbols: [gParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol, rParamSymbol, newRParamSymbol]
            ),
            for: andThenSymbol
        )
    }

    private func registerSyntheticFunctionComposeExtension(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let function1Name = interner.intern("Function1")
        let function1FQName = packageFQName + [function1Name]
        guard let function1Symbol = symbols.lookup(fqName: function1FQName) else { return }

        let composeName = interner.intern("compose")
        let composeFQName = function1FQName + [composeName]

        let composeSymbol = symbols.define(
            kind: .function,
            name: composeName,
            fqName: composeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(function1Symbol, for: composeSymbol)
        symbols.setExternalLinkName("kk_function_compose", for: composeSymbol)

        // 型パラメータの定義
        let newTParamName = interner.intern("NewT")
        let tParamName = interner.intern("T")
        let rParamName = interner.intern("R")

        let newTParamSymbol = symbols.define(
            kind: .typeParameter,
            name: newTParamName,
            fqName: composeFQName + [newTParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: composeFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rParamSymbol = symbols.define(
            kind: .typeParameter,
            name: rParamName,
            fqName: composeFQName + [rParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )

        // パラメータ: g: (NewT) -> T
        let gFunctionType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: newTParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        )))

        let gParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("g"),
            fqName: composeFQName + [interner.intern("g")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(composeSymbol, for: gParamSymbol)

        // 戻り値型: (NewT) -> R
        let returnType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: newTParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        // レシーバ型: (T) -> R
        let receiverType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [gFunctionType],
                returnType: returnType,
                valueParameterSymbols: [gParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [newTParamSymbol, tParamSymbol, rParamSymbol]
            ),
            for: composeSymbol
        )
    }

    private func registerSyntheticFunctionCurriedExtension(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let function2Name = interner.intern("Function2")
        let function2FQName = packageFQName + [function2Name]
        guard let function2Symbol = symbols.lookup(fqName: function2FQName) else { return }

        let curriedName = interner.intern("curried")
        let curriedFQName = function2FQName + [curriedName]

        let curriedSymbol = symbols.define(
            kind: .function,
            name: curriedName,
            fqName: curriedFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(function2Symbol, for: curriedSymbol)
        symbols.setExternalLinkName("kk_function_curried", for: curriedSymbol)

        // 型パラメータの定義
        let p1ParamName = interner.intern("P1")
        let p2ParamName = interner.intern("P2")
        let rParamName = interner.intern("R")

        let p1ParamSymbol = symbols.define(
            kind: .typeParameter,
            name: p1ParamName,
            fqName: curriedFQName + [p1ParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let p2ParamSymbol = symbols.define(
            kind: .typeParameter,
            name: p2ParamName,
            fqName: curriedFQName + [p2ParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rParamSymbol = symbols.define(
            kind: .typeParameter,
            name: rParamName,
            fqName: curriedFQName + [rParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )

        // 戻り値型: (P1) -> (P2) -> R
        let innerFunctionType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: p2ParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))
        let returnType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: p1ParamSymbol, nullability: .nonNull)))],
            returnType: innerFunctionType
        )))

        // レシーバ型: (P1, P2) -> R
        let receiverType = types.make(.functionType(FunctionType(
            params: [
                types.make(.typeParam(TypeParamType(symbol: p1ParamSymbol, nullability: .nonNull))),
                types.make(.typeParam(TypeParamType(symbol: p2ParamSymbol, nullability: .nonNull)))
            ],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [p1ParamSymbol, p2ParamSymbol, rParamSymbol]
            ),
            for: curriedSymbol
        )
    }

    private func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookup(fqName: iterableFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
