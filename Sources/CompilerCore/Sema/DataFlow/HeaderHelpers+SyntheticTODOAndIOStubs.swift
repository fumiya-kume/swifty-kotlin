import Foundation
import RuntimeABI

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

        registerSyntheticIOTopLevelProperty(
            named: "DEFAULT_BUFFER_SIZE",
            packageFQName: kotlinIOPkg,
            returnType: types.intType,
            externalLinkName: "kk_io_default_buffer_size",
            constValue: .intLiteral(8192),
            symbols: symbols,
            interner: interner
        )

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

        registerSyntheticSequenceJoinToMember(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg
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
        let javaClassSymbol = ensureSyntheticJavaLangClassSymbol(
            in: javaLangPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJavaClassExtensionProperty(
            kotlinPkg: kotlinPkg,
            javaClassSymbol: javaClassSymbol,
            symbols: symbols,
            types: types,
            interner: interner
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

    func registerSequenceScopeMember(
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
        let parameterTypes = parameters.map(\.type)
        if symbols.lookupAll(fqName: memberFQName).contains(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameterTypes
        }) {
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
        symbols.setParentSymbol(sequenceScopeSymbol, for: memberSymbol)
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

    func registerSequenceMemberStub(
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
        typeParameterUpperBounds: [TypeID] = [],
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
        let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .sequence,
            memberName: name,
            arity: parameters.count,
            fallback: externalLinkName
        )
        symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
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
                typeParameterUpperBoundsList: [typeParameterUpperBounds] + additionalTypeParameterUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }


    func makeSyntheticIterableType(
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

extension DataFlowSemaPhase {
    fileprivate func ensureSyntheticPackage(
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

    fileprivate func ensureSyntheticPackageHierarchy(
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
}
