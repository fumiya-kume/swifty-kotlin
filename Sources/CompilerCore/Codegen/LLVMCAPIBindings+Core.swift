extension LLVMCAPIBindings {
    func smokeTestContextLifecycle() -> Bool {
        guard let context = contextCreateFn() else {
            return false
        }
        contextDisposeFn(context)
        return true
    }

    func createContext() -> LLVMContextRef? {
        contextCreateFn()
    }

    func disposeContext(_ context: LLVMContextRef?) {
        contextDisposeFn(context)
    }

    func createModule(name: String, context: LLVMContextRef?) -> LLVMModuleRef? {
        name.withCString { moduleCreateFn($0, context) }
    }

    func disposeModule(_ module: LLVMModuleRef?) {
        disposeModuleFn(module)
    }

    func printModule(_ module: LLVMModuleRef?) -> String? {
        guard let raw = printModuleToStringFn(module) else {
            return nil
        }
        defer { disposeMessageFn(raw) }
        return String(cString: raw)
    }

    func setTarget(_ module: LLVMModuleRef?, triple: String) {
        triple.withCString { setTargetFn(module, $0) }
    }

    func setDataLayout(_ module: LLVMModuleRef?, dataLayout: String) {
        dataLayout.withCString { setDataLayoutFn(module, $0) }
    }

    func setExternalWeakLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 12)
    }

    func setWeakAnyLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 5)
    }

    func setInternalLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 8)
    }

    func voidType(context: LLVMContextRef?) -> LLVMTypeRef? {
        voidTypeInContextFn(context)
    }

    func int8Type(context: LLVMContextRef?) -> LLVMTypeRef? {
        int8TypeInContextFn(context)
    }

    func int64Type(context: LLVMContextRef?) -> LLVMTypeRef? {
        int64TypeFn(context)
    }

    func pointerType(_ pointee: LLVMTypeRef?, addressSpace: UInt32 = 0) -> LLVMTypeRef? {
        pointerTypeFn(pointee, addressSpace)
    }

    func functionType(returnType: LLVMTypeRef?, parameters: [LLVMTypeRef?], isVarArg: Bool) -> LLVMTypeRef? {
        var mutable = parameters
        return functionTypeFn(returnType, &mutable, UInt32(mutable.count), isVarArg ? 1 : 0)
    }

    func addFunction(module: LLVMModuleRef?, name: String, functionType: LLVMTypeRef?) -> LLVMValueRef? {
        name.withCString { addFunctionFn(module, $0, functionType) }
    }

    func getNamedFunction(module: LLVMModuleRef?, name: String) -> LLVMValueRef? {
        name.withCString { getNamedFunctionFn(module, $0) }
    }

    func getParam(function: LLVMValueRef?, index: UInt32) -> LLVMValueRef? {
        getParamFn(function, index)
    }

    func getUndef(type: LLVMTypeRef?) -> LLVMValueRef? {
        getUndefFn(type)
    }

    func appendBasicBlock(context: LLVMContextRef?, function: LLVMValueRef?, name: String) -> LLVMBasicBlockRef? {
        name.withCString { appendBasicBlockFn(context, function, $0) }
    }

    func createBuilder(context: LLVMContextRef?) -> LLVMBuilderRef? {
        createBuilderFn(context)
    }

    func disposeBuilder(_ builder: LLVMBuilderRef?) {
        disposeBuilderFn(builder)
    }

    func positionBuilder(_ builder: LLVMBuilderRef?, at block: LLVMBasicBlockRef?) {
        positionBuilderFn(builder, block)
    }

    func hasTerminator(_ block: LLVMBasicBlockRef?) -> Bool {
        getBasicBlockTerminatorFn(block) != nil
    }

    func addGlobal(module: LLVMModuleRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let fn = addGlobalFn else { return nil }
        return name.withCString { fn(module, type, $0) }
    }

    func setInitializer(_ global: LLVMValueRef?, value: LLVMValueRef?) {
        setInitializerFn?(global, value)
    }
}
