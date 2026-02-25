extension LLVMCAPIBindings {
    var debugInfoAvailable: Bool {
        createDIBuilderFn != nil &&
        disposeDIBuilderFn != nil &&
        diBuilderFinalizeFn != nil &&
        diBuilderCreateFileFn != nil &&
        diBuilderCreateCompileUnitFn != nil &&
        diBuilderCreateSubroutineTypeFn != nil &&
        diBuilderCreateFunctionFn != nil &&
        setSubprogramFn != nil &&
        addModuleFlagFn != nil &&
        valueAsMetadataFn != nil &&
        int32TypeFn != nil
    }

    func createDIBuilder(module: LLVMModuleRef?) -> LLVMDIBuilderRef? {
        createDIBuilderFn?(module)
    }

    func disposeDIBuilder(_ builder: LLVMDIBuilderRef?) {
        disposeDIBuilderFn?(builder)
    }

    func finalizeDIBuilder(_ builder: LLVMDIBuilderRef?) {
        diBuilderFinalizeFn?(builder)
    }

    func diBuilderCreateFile(
        _ builder: LLVMDIBuilderRef?,
        filename: String,
        directory: String
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateFileFn else { return nil }
        return filename.withCString { fName in
            directory.withCString { dir in
                diBuilderCreateFileFn(builder, fName, filename.utf8.count, dir, directory.utf8.count)
            }
        }
    }

    func diBuilderCreateCompileUnit(
        _ builder: LLVMDIBuilderRef?,
        lang: UInt32,
        file: LLVMMetadataRef?,
        producer: String,
        isOptimized: Bool
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateCompileUnitFn else { return nil }
        return producer.withCString { prod in
            "".withCString { empty in
                diBuilderCreateCompileUnitFn(
                    builder,
                    lang, file,
                    prod, producer.utf8.count,
                    isOptimized ? 1 : 0,
                    empty, 0,
                    0,
                    empty, 0,
                    1,
                    0, 0, 0,
                    empty, 0,
                    empty, 0
                )
            }
        }
    }

    func diBuilderCreateSubroutineType(
        _ builder: LLVMDIBuilderRef?,
        file: LLVMMetadataRef?,
        parameterTypes: [LLVMMetadataRef?]
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateSubroutineTypeFn else { return nil }
        var mutable = parameterTypes
        return diBuilderCreateSubroutineTypeFn(
            builder, file, &mutable, UInt32(mutable.count), 0
        )
    }

    func diBuilderCreateFunction(
        _ builder: LLVMDIBuilderRef?,
        scope: LLVMMetadataRef?,
        name: String,
        linkageName: String,
        file: LLVMMetadataRef?,
        lineNo: UInt32,
        type: LLVMMetadataRef?,
        isLocalToUnit: Bool,
        isDefinition: Bool,
        scopeLine: UInt32,
        isOptimized: Bool
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateFunctionFn else { return nil }
        return name.withCString { n in
            linkageName.withCString { ln in
                diBuilderCreateFunctionFn(
                    builder, scope,
                    n, name.utf8.count,
                    ln, linkageName.utf8.count,
                    file,
                    lineNo, type,
                    isLocalToUnit ? 1 : 0,
                    isDefinition ? 1 : 0,
                    scopeLine, 0,
                    isOptimized ? 1 : 0
                )
            }
        }
    }

    func setSubprogram(_ function: LLVMValueRef?, subprogram: LLVMMetadataRef?) {
        setSubprogramFn?(function, subprogram)
    }

    func addModuleFlag(
        _ module: LLVMModuleRef?,
        behavior: UInt32,
        key: String,
        value: LLVMMetadataRef?
    ) {
        guard let addModuleFlagFn else { return }
        key.withCString { k in
            addModuleFlagFn(module, behavior, k, key.utf8.count, value)
        }
    }

    func valueAsMetadata(_ value: LLVMValueRef?) -> LLVMMetadataRef? {
        valueAsMetadataFn?(value)
    }

    func int32Type(context: LLVMContextRef?) -> LLVMTypeRef? {
        int32TypeFn?(context)
    }

    var debugLocationAvailable: Bool {
        setCurrentDebugLocation2Fn != nil && diBuilderCreateDebugLocationFn != nil
    }

    func createDebugLocation(
        context: LLVMContextRef?,
        line: UInt32,
        column: UInt32,
        scope: LLVMMetadataRef?,
        inlinedAt: LLVMMetadataRef? = nil
    ) -> LLVMMetadataRef? {
        diBuilderCreateDebugLocationFn?(context, line, column, scope, inlinedAt)
    }

    func setCurrentDebugLocation(_ builder: LLVMBuilderRef?, location: LLVMMetadataRef?) {
        setCurrentDebugLocation2Fn?(builder, location)
    }

    func clearCurrentDebugLocation(_ builder: LLVMBuilderRef?) {
        setCurrentDebugLocation2Fn?(builder, nil)
    }

    var localVariableAvailable: Bool {
        diBuilderCreateBasicTypeFn != nil &&
        diBuilderCreateParameterVariableFn != nil &&
        diBuilderInsertDeclareAtEndFn != nil &&
        diBuilderCreateExpressionFn != nil
    }

    func diBuilderCreateBasicType(
        _ builder: LLVMDIBuilderRef?,
        name: String,
        sizeInBits: UInt64,
        encoding: UInt32
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateBasicTypeFn else { return nil }
        return name.withCString { n in
            diBuilderCreateBasicTypeFn(builder, n, name.utf8.count, sizeInBits, encoding, 0)
        }
    }

    func diBuilderCreateParameterVariable(
        _ builder: LLVMDIBuilderRef?,
        scope: LLVMMetadataRef?,
        name: String,
        argNo: UInt32,
        file: LLVMMetadataRef?,
        lineNo: UInt32,
        type: LLVMMetadataRef?
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateParameterVariableFn else { return nil }
        return name.withCString { n in
            diBuilderCreateParameterVariableFn(
                builder, scope, n, name.utf8.count, argNo, file, lineNo, type, 0, 0  // AlwaysPreserve=0, Flags=0
            )
        }
    }

    func diBuilderCreateAutoVariable(
        _ builder: LLVMDIBuilderRef?,
        scope: LLVMMetadataRef?,
        name: String,
        file: LLVMMetadataRef?,
        lineNo: UInt32,
        type: LLVMMetadataRef?
    ) -> LLVMMetadataRef? {
        guard let diBuilderCreateAutoVariableFn else { return nil }
        return name.withCString { n in
            diBuilderCreateAutoVariableFn(
                builder, scope, n, name.utf8.count, file, lineNo, type, 0, 0, 0
            )
        }
    }

    func diBuilderInsertDeclareAtEnd(
        _ builder: LLVMDIBuilderRef?,
        storage: LLVMValueRef?,
        varInfo: LLVMMetadataRef?,
        expr: LLVMMetadataRef?,
        debugLoc: LLVMMetadataRef?,
        block: LLVMBasicBlockRef?
    ) -> LLVMValueRef? {
        diBuilderInsertDeclareAtEndFn?(builder, storage, varInfo, expr, debugLoc, block)
    }

    func diBuilderCreateExpression(
        _ builder: LLVMDIBuilderRef?
    ) -> LLVMMetadataRef? {
        diBuilderCreateExpressionFn?(builder, nil, 0)
    }
}
