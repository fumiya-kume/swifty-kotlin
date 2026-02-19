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
}
