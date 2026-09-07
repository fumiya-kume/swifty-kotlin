import Foundation
import RuntimeABI

import CompilerCore

/// Counter for deterministic generated names in LLVM IR output.
final class GeneratedNameCounter {
    private var value: Int32 = 0

    func next() -> Int32 {
        let current = value
        value += 1
        return current
    }

    func nextName(_ prefix: String) -> String {
        "\(prefix)\(next())"
    }
}

struct NativeEmitter {
    /// DWARF constants used across the emitter.
    /// DW_LANG_C99 – used as the compile-unit language tag.
    static let dwarfLangC99: UInt32 = 11
    /// DW_ATE_signed – DWARF attribute encoding for signed integers.
    static let dwarfATESigned: UInt32 = 5

    /// Legacy void/no-argument runtime call set retained for ABI compatibility.
    /// Print and println are source-backed, so this intentionally stays empty.
    static let knownVoidNoArgCallees: Set<String> = []

    // These calls receive a function value as their first argument; the KIR
    // symbol is only an inline-lowering hint and never a direct native callee.
    static let functionValueInvokeCallees: Set<String> = [
        "kk_function_invoke", "kk_function_invoke_0",
        "kk_function_invoke_2", "kk_function_invoke_3", "kk_function_invoke_4",
        "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2",
    ]

    /// Quick lookup for runtime ABI function specs by symbol name.
    static let runtimeABIFunctionByName: [String: RuntimeABIFunctionSpec] = {
        Dictionary(uniqueKeysWithValues: RuntimeABISpec.allFunctions.map { ($0.name, $0) })
    }()

    struct LLVMFunction {
        let value: LLVMCAPIBindings.LLVMValueRef
        let type: LLVMCAPIBindings.LLVMTypeRef
    }

    /// Lookup key used to resolve internal functions by either their KIR name
    /// or generated C symbol name plus user parameter count.
    struct FunctionLookupKey: Hashable {
        let name: String
        let parameterCount: Int
    }

    struct DebugInfoContext {
        let diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef
        let file: LLVMCAPIBindings.LLVMMetadataRef
        let subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef]
        /// Per-file DI file metadata keyed by FileID.
        let diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef]
        /// DI basic type for i64 (used for parameter/variable debug info).
        let int64DIType: LLVMCAPIBindings.LLVMMetadataRef?
    }

    let target: TargetTriple
    let optLevel: OptimizationLevel
    let debugInfo: Bool
    let bindings: LLVMCAPIBindings
    let module: KIRModule
    let interner: StringInterner
    let typeSystem: TypeSystem?
    let symbols: SymbolTable?
    let sourceManager: SourceManager?
    let fileFacadeNamesByFileID: [Int32: String]
    /// REFL-004: Metadata records to embed as runtime reflection metadata.
    let reflectionMetadataRecords: [MetadataRecord]
    let reflectionMetadataSymbolPrefix: String?
    /// Symbols that should use linkonce_odr linkage (e.g. bundled stdlib functions compiled into
    /// multiple compilation units). The linker deduplicates linkonce_odr definitions automatically.
    let linkOnceODRSymbols: Set<SymbolID>

    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        bindings: LLVMCAPIBindings,
        module: KIRModule,
        interner: StringInterner,
        typeSystem: TypeSystem? = nil,
        symbols: SymbolTable? = nil,
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil,
        linkOnceODRSymbols: Set<SymbolID> = []
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.bindings = bindings
        self.module = module
        self.interner = interner
        self.typeSystem = typeSystem
        self.symbols = symbols
        self.sourceManager = sourceManager
        self.fileFacadeNamesByFileID = fileFacadeNamesByFileID
        self.reflectionMetadataRecords = reflectionMetadataRecords
        self.reflectionMetadataSymbolPrefix = reflectionMetadataSymbolPrefix
        self.linkOnceODRSymbols = linkOnceODRSymbols
    }

    private func collectRuntimeCallbackRawABISymbols() -> Set<SymbolID> {
        Self.collectRuntimeCallbackRawABISymbols(module: module, interner: interner, symbols: symbols)
    }

    static func collectRuntimeCallbackRawStringReturnSymbols(
        module: KIRModule,
        interner: StringInterner,
        typeSystem: TypeSystem?,
        symbols: SymbolTable? = nil
    ) -> Set<SymbolID> {
        let rawSymbols = collectRuntimeCallbackRawABISymbols(module: module, interner: interner, symbols: symbols)
        guard let typeSystem else { return [] }
        return Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .function(function) = declaration else { return nil }
            guard rawSymbols.contains(function.symbol) else { return nil }
            guard case .stringStruct = typeSystem.kind(of: function.returnType) else { return nil }
            return function.symbol
        })
    }

    static func collectRuntimeCallbackRawABISymbols(
        module: KIRModule,
        interner: StringInterner,
        symbols: SymbolTable? = nil
    ) -> Set<SymbolID> {
        let callbackArgumentPositionsByCallee = runtimeCallbackArgumentPositionsByCallee(interner: interner)
        guard !callbackArgumentPositionsByCallee.isEmpty else {
            return []
        }

        var rawSymbols: Set<SymbolID> = []
        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration else {
                continue
            }
            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, _, _, _, _, _):
                    guard let callbackPositions = callbackArgumentPositionsByCallee[callee] else {
                        continue
                    }
                    for position in callbackPositions where arguments.indices.contains(position) {
                        if case let .symbolRef(symbol)? = module.arena.expr(arguments[position]) {
                            rawSymbols.insert(symbol)
                        }
                    }

                default:
                    continue
                }
            }
        }
        if !rawSymbols.isEmpty {
            // Dispatch declarations and concrete overrides must share the callback ABI
            // when a same-shaped implementation is registered for reflection.
            struct FunctionABIKey: Hashable {
                let name: InternedString
                let parameterCount: Int
            }

            var rawCallbackKeys: Set<FunctionABIKey> = []
            for declaration in module.arena.declarations {
                guard case let .function(function) = declaration,
                      rawSymbols.contains(function.symbol),
                      Self.isSyntheticCallbackFunction(function, symbols: symbols, interner: interner)
                else {
                    continue
                }
                rawCallbackKeys.insert(FunctionABIKey(
                    name: function.name,
                    parameterCount: function.params.count
                ))
            }
            for declaration in module.arena.declarations {
                guard case let .function(function) = declaration else {
                    continue
                }
                let key = FunctionABIKey(name: function.name, parameterCount: function.params.count)
                if rawCallbackKeys.contains(key), Self.isSyntheticCallbackFunction(function, symbols: symbols, interner: interner) {
                    rawSymbols.insert(function.symbol)
                }
            }
        }

        // Throwable.toString uses the runtime's raw string-handle ABI for both
        // the bundled implementation and Kotlin-defined overrides. This keeps
        // the vtable slot ABI uniform with the runtime bridge; call sites bridge
        // the raw handle back to the Kotlin String aggregate.
        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration,
                  isThrowableToStringFunction(function, interner: interner, symbols: symbols)
            else {
                continue
            }
            rawSymbols.insert(function.symbol)
        }

        return rawSymbols
    }

    private static func isThrowableToStringFunction(
        _ function: KIRFunction,
        interner: StringInterner,
        symbols: SymbolTable?
    ) -> Bool {
        guard interner.resolve(function.name) == "toString",
              let symbols,
              isThrowableToStringSymbol(function.symbol, interner: interner, symbols: symbols)
        else {
            return false
        }
        return true
    }

    static func isThrowableToStringSymbol(
        _ symbol: SymbolID,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> Bool {
        guard let owner = symbols.parentSymbol(for: symbol) else {
            return false
        }
        return isThrowableClassSymbol(owner, interner: interner, symbols: symbols)
    }

    static func isThrowableType(
        _ type: TypeID?,
        typeSystem: TypeSystem,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> Bool {
        guard let type,
              case let .classType(classType) = typeSystem.kind(of: type)
        else {
            return false
        }
        return isThrowableClassSymbol(
            classType.classSymbol,
            interner: interner,
            symbols: symbols
        )
    }

    private static func isThrowableClassSymbol(
        _ symbol: SymbolID,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> Bool {
        let throwableFQName = ["kotlin", "Throwable"]
        var visited: Set<SymbolID> = []
        var pending = [symbol]
        while let candidate = pending.popLast() {
            guard visited.insert(candidate).inserted,
                  let symbolInfo = symbols.symbol(candidate)
            else {
                continue
            }
            if symbolInfo.fqName.map(interner.resolve) == throwableFQName {
                return true
            }
            pending.append(contentsOf: symbols.directSupertypes(for: candidate))
        }
        return false
    }

    private static func isSyntheticCallbackFunction(
        _ function: KIRFunction,
        symbols: SymbolTable?,
        interner: StringInterner
    ) -> Bool {
        guard let symbols else { return true }
        guard let symbolInfo = symbols.symbol(function.symbol) else { return false }
        return symbolInfo.flags.contains(.synthetic)
    }

    private static func runtimeCallbackArgumentPositionsByCallee(
        interner: StringInterner
    ) -> [InternedString: [Int]] {
        var positionsByCallee: [InternedString: [Int]] = [:]
        for spec in RuntimeABISpec.allFunctions {
            if spec.name == "kk_object_register_itable_method"
                || spec.name == "kk_object_register_vtable_method"
                || spec.name.hasPrefix("__kk_kfunction_create")
                || spec.name == "__kk_kconstructor_create" {
                continue
            }
            var positions: [Int] = []
            var abiIndex = 0
            var kirIndex = 0
            while abiIndex < spec.parameters.count {
                let parameter = spec.parameters[abiIndex]
                let name = parameter.name.lowercased()
                // bodyRaw: kk_function_create_* stores adapter/lambda bodies invoked via
                // kk_function_invoke, which uses the flat intptr callback ABI.
                // selFn/cFn: comparator selector/comparator function pointers passed to
                // RuntimeCollectionLambda1-compatible callbacks (e.g. kk_list_sortedBy).
                if name.contains("fnptr") || name == "functionraw" || name == "bodyraw" || name.hasSuffix("fn") {
                    positions.append(kirIndex)
                }
                if abiIndex + 3 < spec.parameters.count,
                   name.hasSuffix("data")
                {
                    let prefix = String(name.dropLast("data".count))
                    let lengthName = spec.parameters[abiIndex + 1].name.lowercased()
                    let byteCountName = spec.parameters[abiIndex + 2].name.lowercased()
                    let hashName = spec.parameters[abiIndex + 3].name.lowercased()
                    if lengthName == "\(prefix)length",
                       byteCountName == "\(prefix)bytecount",
                       hashName == "\(prefix)hash"
                    {
                        kirIndex += 1
                        abiIndex += 4
                        continue
                    }
                }
                kirIndex += 1
                abiIndex += 1
            }
            if !positions.isEmpty {
                positionsByCallee[interner.intern(spec.name)] = positions
            }
        }
        return positionsByCallee
    }

    func emitLLVMIR(outputPath: String) throws {
        let built = try buildModule()
        defer {
            bindings.disposeModule(built.module)
            bindings.disposeContext(built.context)
        }

        let triple = targetTripleString()
        // LLVM's target registry and module printing both touch process-global
        // state on Linux, so keep the entire target-and-print sequence under the
        // same process lock used for object emission.
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
            bindings.setTarget(built.module, triple: triple)

            guard let llvmIR = bindings.printModule(built.module) else {
                throw LLVMBackendError.nativeEmissionFailed("LLVMPrintModuleToString returned null")
            }
            do {
                try llvmIR.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            } catch {
                throw LLVMBackendError.nativeEmissionFailed("failed to write LLVM IR to '\(outputPath)'")
            }
        }
    }

    func emitObject(outputPath: String) throws {
        let built = try buildModule()
        defer {
            bindings.disposeModule(built.module)
            bindings.disposeContext(built.context)
        }

        // LLVM target registration and native emission use process-global state
        // on Linux. Keep module construction parallel, but serialize only the
        // target-machine section that is not thread-safe.
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
            var triple = targetTripleString()
            bindings.setTarget(built.module, triple: triple)

            var targetMachine = bindings.createTargetMachine(triple: triple, optLevel: optLevel)
            if targetMachine == nil,
               let hostTriple = bindings.defaultTargetTriple(),
               !hostTriple.isEmpty,
               hostTriple != triple
            {
                triple = hostTriple
                bindings.setTarget(built.module, triple: triple)
                targetMachine = bindings.createTargetMachine(triple: hostTriple, optLevel: optLevel)
            }

            guard let targetMachine else {
                throw LLVMBackendError.nativeEmissionFailed("failed to create LLVM target machine")
            }
            defer { bindings.disposeTargetMachine(targetMachine) }

            guard bindings.applyTargetMachine(targetMachine, to: built.module) else {
                throw LLVMBackendError.nativeEmissionFailed("failed to apply target data layout")
            }

            if let errorMessage = bindings.emitObject(targetMachine: targetMachine, module: built.module, outputPath: outputPath) {
                throw LLVMBackendError.nativeEmissionFailed(errorMessage)
            }
        }
    }

    /// Returns a stable C-compatible LLVM global slot name for the given symbol.
    /// For globals with a known fully-qualified name (e.g. properties and object
    /// singletons) the name is derived from that FQN so that a precompiled
    /// library and its consumers refer to the same storage. Otherwise it falls
    /// back to the raw symbol identifier for backwards compatibility.
    fileprivate func stableGlobalSlotName(for symbol: SymbolID) -> String {
        if let sym = symbols?.symbol(symbol) {
            let fqn = sym.fqName.compactMap { interner.resolve($0) }.joined(separator: ".")
            if !fqn.isEmpty {
                let sanitized = fqn.map { c in
                    c.isLetter || c.isNumber || c == "_" ? String(c) : "_"
                }.joined()
                return "kk_global_root_slot_\(sanitized)"
            }
        }
        return "kk_global_root_slot_\(max(0, Int(symbol.rawValue)))"
    }

    /// Returns true for imported-library symbols that are expected to be
    /// backed by a global variable in the linked object (properties, fields,
    /// backing fields, and top-level objects). Companion objects are excluded
    /// because their functions are emitted as static-like receivers and they
    /// do not allocate a singleton global.
    private func shouldEmitImportedGlobalReference(for symbol: SymbolID) -> Bool {
        guard let sym = symbols?.symbol(symbol),
              sym.flags.contains(.importedLibrary)
        else {
            return false
        }
        switch sym.kind {
        case .property, .field, .backingField:
            return true
        case .object:
            // Top-level object singletons have a global instance.
            // Companion objects only need one when their virtual methods
            // require a runtime receiver and vtable.
            if let parentID = symbols?.parentSymbol(for: symbol),
               let parent = symbols?.symbol(parentID),
               parent.kind != .package,
               symbols?.nominalLayout(for: symbol)?.vtableSize ?? 0 == 0 {
                return false
            }
            // Synthetic singleton stubs (e.g. kotlin.system.System) have no
            // backing state and no initializer, so their global slot is never
            // emitted. Returning zero for their symbolRef is safe because the
            // only uses are as receivers for static-like runtime bridges that
            // discard the receiver.
            if symbols?.objectInitializerSymbol(for: symbol) == nil,
               symbols?.externalLinkName(for: symbol)?.isEmpty != false,
               symbols?.nominalLayout(for: symbol)?.instanceFieldCount == 0 {
                return false
            }
            return true
        case .class, .interface, .enumClass, .annotationClass, .typeAlias,
             .function, .constructor, .typeParameter, .valueParameter,
             .local, .label, .package:
            return false
        }
    }

    /// Residual synthetic objects (for example `kotlin.system.System`) have no
    /// object initializer in the precompiled stdlib artifact. Their singleton
    /// receiver is only an ABI handle, so a consumer may keep an unresolved
    /// weak root slot instead of requiring a definition that the artifact
    /// intentionally does not export.
    private func shouldUseWeakImportedGlobalReference(for symbol: SymbolID) -> Bool {
        guard let symbols else { return false }
        return Self.shouldUseWeakImportedObjectGlobalReference(for: symbol, symbols: symbols)
    }

    /// Returns the weak-linkage decision for an imported object global.
    /// A non-package parent is not sufficient to identify a companion object:
    /// regular nested objects must use their own initializer metadata.
    static func shouldUseWeakImportedObjectGlobalReference(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        guard let sym = symbols.symbol(symbol), sym.kind == .object else {
            return false
        }
        if let parentID = symbols.parentSymbol(for: symbol),
           symbols.companionObjectSymbol(for: parentID) == symbol
        {
            return symbols.companionObjectInitializerSymbol(for: parentID) == nil
        }
        return symbols.objectInitializerSymbol(for: symbol) == nil
    }

    /// Ensures that any imported-library global referenced by `loadGlobal`,
    /// `storeGlobal`, or `symbolRef` has an LLVM global declaration in the
    /// current module. Without this, the backend silently emits zero for
    /// references to globals defined in a precompiled `.kklib` (e.g.
    /// `Uuid.Companion.NIL`) because those globals are not present in the
    /// current module's KIR global declarations.
    private func ensureImportedGlobalReferences(
        module: KIRModule,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        globalVariables: inout [SymbolID: LLVMCAPIBindings.LLVMValueRef]
    ) {
        var referencedSymbols: Set<SymbolID> = []
        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration else {
                continue
            }
            for instruction in function.body {
                switch instruction {
                case let .loadGlobal(_, symbol), let .storeGlobal(_, symbol):
                    referencedSymbols.insert(symbol)
                case let .constValue(_, .symbolRef(symbol)):
                    referencedSymbols.insert(symbol)
                default:
                    break
                }
            }
        }
        for expr in module.arena.expressions {
            if case let .symbolRef(symbol) = expr {
                referencedSymbols.insert(symbol)
            }
        }
        for symbol in referencedSymbols.sorted(by: { stableGlobalSlotName(for: $0) < stableGlobalSlotName(for: $1) }) {
            guard globalVariables[symbol] == nil,
                  shouldEmitImportedGlobalReference(for: symbol) || shouldUseWeakImportedGlobalReference(for: symbol)
            else {
                continue
            }
            let slotName = stableGlobalSlotName(for: symbol)
            if let llvmGlobal = bindings.addGlobal(module: llvmModule, type: int64Type, name: slotName) {
                if shouldUseWeakImportedGlobalReference(for: symbol) {
                    bindings.setWeakAnyLinkage(llvmGlobal)
                    if let zero = bindings.constInt(int64Type, value: 0) {
                        bindings.setInitializer(llvmGlobal, value: zero)
                    }
                } else {
                    bindings.setExternalLinkage(llvmGlobal)
                }
                globalVariables[symbol] = llvmGlobal
            }
        }
    }

    func buildModule() throws -> (
        context: LLVMCAPIBindings.LLVMContextRef,
        module: LLVMCAPIBindings.LLVMModuleRef
    ) {
        guard let context = bindings.createContext() else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMContextCreate returned null")
        }
        guard let llvmModule = bindings.createModule(name: "kswiftk_module", context: context) else {
            bindings.disposeContext(context)
            throw LLVMBackendError.nativeEmissionFailed("LLVMModuleCreateWithNameInContext returned null")
        }

        guard let int64Type = bindings.int64Type(context: context) else {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw LLVMBackendError.nativeEmissionFailed("LLVMInt64TypeInContext returned null")
        }
        guard let outThrownPointerType = bindings.pointerType(int64Type, addressSpace: 0) else {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw LLVMBackendError.nativeEmissionFailed("LLVMPointerType returned null")
        }
        let typeLowering = makeLLVMTypeLowering(context: context, int64Type: int64Type)
        let runtimeCallbackRawABISymbols = collectRuntimeCallbackRawABISymbols()

        func isStringAggregateType(_ type: TypeID?) -> Bool {
            guard let type,
                  let typeSystem,
                  case .stringStruct = typeSystem.kind(of: type)
            else {
                return false
            }
            return typeLowering != nil
        }

        do {
            try defineWeakFrameRuntimeStubs(
                module: llvmModule,
                context: context,
                int64Type: int64Type
            )
        } catch {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw error
        }

        // Create LLVM global variables for each KIR global declaration.
        // Globals that back properties/singletons shared across .kklib modules
        // are named by their stable fully-qualified name so a consumer object
        // can reference the same storage defined in the library object.
        var llvmGlobalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        let globalDecls = module.arena.declarations.compactMap { decl -> KIRGlobal? in
            guard case let .global(global) = decl else { return nil }
            return global
        }.sorted { lhs, rhs in
            let lhsName = stableGlobalSlotName(for: lhs.symbol)
            let rhsName = stableGlobalSlotName(for: rhs.symbol)
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.symbol.rawValue < rhs.symbol.rawValue
        }
        for global in globalDecls {
            let slotName = stableGlobalSlotName(for: global.symbol)
            let isImported = symbols?.symbol(global.symbol)?.flags.contains(.importedLibrary) == true
            if let llvmGlobal = bindings.addGlobal(module: llvmModule, type: int64Type, name: slotName) {
                if isImported {
                    // Imported globals are defined in another object file.
                    if shouldUseWeakImportedGlobalReference(for: global.symbol) {
                        bindings.setWeakAnyLinkage(llvmGlobal)
                        if let zero = bindings.constInt(int64Type, value: 0) {
                            bindings.setInitializer(llvmGlobal, value: zero)
                        }
                    } else {
                        bindings.setExternalLinkage(llvmGlobal)
                    }
                } else {
                    // Use linkonce_odr so multiple compilation units (e.g. a
                    // precompiled stdlib .kklib and a consuming module) can each
                    // contain a tentative definition of the same global; the
                    // linker keeps one copy and all references resolve to it.
                    bindings.setLinkOnceODRLinkage(llvmGlobal)
                    if let zero = bindings.constInt(int64Type, value: 0) {
                        bindings.setInitializer(llvmGlobal, value: zero)
                    }
                }
                llvmGlobalVariables[global.symbol] = llvmGlobal
            }
        }

        // Imported-library globals (e.g. `Uuid.Companion.NIL`) are referenced by
        // `loadGlobal`/`symbolRef` in the consumer module but are not present in
        // the consumer's KIR global declarations because they live in the
        // precompiled `.kklib`. Emit external declarations for them so the backend
        // resolves them to the library definition instead of returning zero.
        ensureImportedGlobalReferences(
            module: module,
            llvmModule: llvmModule,
            int64Type: int64Type,
            globalVariables: &llvmGlobalVariables
        )

        var internalFunctions: [SymbolID: LLVMFunction] = [:]
        var internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)] = [:]
        var internalFunctionsByLookupKey: [FunctionLookupKey: [KIRFunction]] = [:]
        var emittableFunctions: [(KIRFunction, String)] = []

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration,
                  !function.isInlineOnly
            else {
                continue
            }
            let functionName = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: interner,
                symbols: symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            let usesRuntimeCallbackRawABI = runtimeCallbackRawABISymbols.contains(function.symbol)
            var parameterTypes = function.params.map {
                if usesRuntimeCallbackRawABI {
                    return int64Type
                }
                return loweredLLVMType(
                    for: $0.type,
                    lowering: typeLowering,
                    defaultType: int64Type
                )
            }
            parameterTypes.append(outThrownPointerType)
            let returnsRawStringRuntimeCallback = usesRuntimeCallbackRawABI && isStringAggregateType(function.returnType)
            let returnType = if returnsRawStringRuntimeCallback {
                int64Type
            } else {
                loweredLLVMType(
                    for: function.returnType,
                    lowering: typeLowering,
                    defaultType: int64Type
                )
            }

            guard let functionType = bindings.functionType(returnType: returnType, parameters: parameterTypes, isVarArg: false),
                  let functionValue = bindings.addFunction(module: llvmModule, name: functionName, functionType: functionType)
            else {
                bindings.disposeModule(llvmModule)
                bindings.disposeContext(context)
                throw LLVMBackendError.nativeEmissionFailed("failed to declare function '\(functionName)'")
            }
            if linkOnceODRSymbols.contains(function.symbol) {
                bindings.setLinkOnceODRLinkage(functionValue)
            }
            internalFunctions[function.symbol] = LLVMFunction(value: functionValue, type: functionType)
            internalSignatures[function.symbol] = (function.params.map(\.type), function.returnType)
            let functionLookupKey = FunctionLookupKey(name: interner.resolve(function.name), parameterCount: function.params.count)
            let cSymbolLookupKey = FunctionLookupKey(name: functionName, parameterCount: function.params.count)
            internalFunctionsByLookupKey[functionLookupKey, default: []].append(function)
            internalFunctionsByLookupKey[cSymbolLookupKey, default: []].append(function)
            emittableFunctions.append((function, functionName))
        }

        do {
            let diContext: DebugInfoContext? = (debugInfo && bindings.debugLocationAvailable)
                ? createDebugInfoContext(
                    llvmModule: llvmModule,
                    context: context,
                    internalFunctions: internalFunctions
                )
                : nil

            let nameCounter = GeneratedNameCounter()
            emittableFunctions.sort { $0.1 < $1.1 }
            for (function, _) in emittableFunctions {
                guard let llvmFunction = internalFunctions[function.symbol] else { continue }
                do {
                    let usesRuntimeCallbackRawABI = runtimeCallbackRawABISymbols.contains(function.symbol)
                    let returnsRawStringRuntimeCallback = usesRuntimeCallbackRawABI
                        && isStringAggregateType(function.returnType)
                    try emitFunctionBody(
                        function: function,
                        llvmFunction: llvmFunction,
                        llvmModule: llvmModule,
                        context: context,
                        int64Type: int64Type,
                        typeLowering: typeLowering,
                        outThrownPointerType: outThrownPointerType,
                        internalFunctions: internalFunctions,
                        internalSignatures: internalSignatures,
                        internalFunctionsByLookupKey: internalFunctionsByLookupKey,
                        globalVariables: llvmGlobalVariables,
                        runtimeCallbackRawReturnSymbols: runtimeCallbackRawABISymbols,
                        usesRuntimeCallbackRawABI: usesRuntimeCallbackRawABI,
                        returnsRawStringRuntimeCallback: returnsRawStringRuntimeCallback,
                        nameCounter: nameCounter,
                        diContext: diContext
                    )
                } catch {
                    if let diContext {
                        bindings.disposeDIBuilder(diContext.diBuilder)
                    }
                    bindings.disposeModule(llvmModule)
                    bindings.disposeContext(context)
                    throw error
                }
            }

            if let diContext {
                finalizeDebugInfo(
                    diContext: diContext,
                    llvmModule: llvmModule,
                    context: context
                )
            }
        }

        // REFL-004: Emit runtime reflection metadata as global constants.
        RuntimeReflectionMetadataEmitter.emitGlobals(
            records: reflectionMetadataRecords,
            bindings: bindings,
            module: llvmModule,
            context: context,
            int64Type: int64Type,
            symbolPrefix: reflectionMetadataSymbolPrefix
        )

        return (context: context, module: llvmModule)
    }

    /// Creates debug info metadata (DIBuilder, compile unit, file, subprograms)
    /// BEFORE function bodies are emitted so that debug locations can be set
    /// on instructions during emission.
    func createDebugInfoContext(
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context _: LLVMCAPIBindings.LLVMContextRef,
        internalFunctions: [SymbolID: LLVMFunction]
    ) -> DebugInfoContext? {
        guard bindings.debugInfoAvailable else {
            return nil
        }

        guard let diBuilder = bindings.createDIBuilder(module: llvmModule) else {
            return nil
        }

        // Determine the primary source file from the SourceManager if available.
        let primaryFilename: String
        let primaryDirectory: String
        if let sourceManager, sourceManager.fileCount > 0 {
            let firstFileID = FileID(rawValue: 0)
            let fullPath = sourceManager.path(of: firstFileID)
            let url = URL(fileURLWithPath: fullPath)
            primaryFilename = url.lastPathComponent
            let directoryPath = url.deletingLastPathComponent().path
            primaryDirectory = directoryPath.isEmpty ? "." : directoryPath
        } else {
            primaryFilename = "kswiftk_module.kt"
            primaryDirectory = "."
        }

        guard let diFile = bindings.diBuilderCreateFile(
            diBuilder,
            filename: primaryFilename,
            directory: primaryDirectory
        ) else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let isOptimized = optLevel != .O0
        // The compile unit must be created so the module's debug info is well-formed,
        // even though the resulting handle is not retained on DebugInfoContext.
        guard bindings.diBuilderCreateCompileUnit(
            diBuilder,
            lang: Self.dwarfLangC99,
            file: diFile,
            producer: "kswiftk",
            isOptimized: isOptimized
        ) != nil else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let subroutineType = bindings.diBuilderCreateSubroutineType(
            diBuilder,
            file: diFile,
            parameterTypes: []
        )

        // Build per-file DI metadata so that functions can reference their
        // actual source file.
        let diFiles = buildDIFiles(diBuilder: diBuilder, defaultFile: diFile)
        let int64DIType = bindings.diBuilderCreateBasicType(
            diBuilder, name: "Int", sizeInBits: 64, encoding: Self.dwarfATESigned
        )
        let subprograms = buildSubprograms(
            diBuilder: diBuilder, diFile: diFile, diFiles: diFiles,
            subroutineType: subroutineType, isOptimized: isOptimized,
            internalFunctions: internalFunctions
        )

        return DebugInfoContext(
            diBuilder: diBuilder,
            file: diFile,
            subprograms: subprograms,
            diFiles: diFiles,
            int64DIType: int64DIType
        )
    }

    private func buildDIFiles(
        diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef,
        defaultFile _: LLVMCAPIBindings.LLVMMetadataRef
    ) -> [FileID: LLVMCAPIBindings.LLVMMetadataRef] {
        var diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef] = [:]
        guard let sourceManager else { return diFiles }
        for fileID in sourceManager.fileIDs() {
            let fullPath = sourceManager.path(of: fileID)
            let url = URL(fileURLWithPath: fullPath)
            let fname = url.lastPathComponent
            let dir = url.deletingLastPathComponent().path
            if let f = bindings.diBuilderCreateFile(diBuilder, filename: fname, directory: dir) {
                diFiles[fileID] = f
            }
        }
        return diFiles
    }

    private func buildSubprograms(
        diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef,
        diFile: LLVMCAPIBindings.LLVMMetadataRef,
        diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef],
        subroutineType: LLVMCAPIBindings.LLVMMetadataRef?,
        isOptimized: Bool,
        internalFunctions: [SymbolID: LLVMFunction]
    ) -> [SymbolID: LLVMCAPIBindings.LLVMMetadataRef] {
        var subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef] = [:]
        let functions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl,
                  internalFunctions[function.symbol] != nil
            else { return nil }
            return function
        }.sorted { lhs, rhs in
            let lhsName = CodegenSymbolSupport.cFunctionSymbol(
                for: lhs,
                interner: interner,
                symbols: symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            let rhsName = CodegenSymbolSupport.cFunctionSymbol(
                for: rhs,
                interner: interner,
                symbols: symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.symbol.rawValue < rhs.symbol.rawValue
        }
        for function in functions {
            guard let llvmFunction = internalFunctions[function.symbol] else { continue }
            let functionName = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: interner,
                symbols: symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            var lineNo: UInt32 = 0
            var funcDIFile = diFile
            if let sourceRange = function.sourceRange, let sourceManager {
                let lc = sourceManager.lineColumn(of: sourceRange.start)
                lineNo = UInt32(lc.line)
                if let perFileDI = diFiles[sourceRange.start.file] { funcDIFile = perFileDI }
            }
            guard let subprogram = bindings.diBuilderCreateFunction(
                diBuilder, scope: funcDIFile,
                name: interner.resolve(function.name), linkageName: functionName,
                file: funcDIFile, lineNo: lineNo, type: subroutineType,
                isLocalToUnit: false, isDefinition: true, scopeLine: lineNo, isOptimized: isOptimized
            ) else { continue }
            bindings.setSubprogram(llvmFunction.value, subprogram: subprogram)
            subprograms[function.symbol] = subprogram
        }
        return subprograms
    }

    /// Finalizes the DIBuilder, adds module flags, and disposes the DIBuilder.
    func finalizeDebugInfo(
        diContext: DebugInfoContext,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef
    ) {
        bindings.finalizeDIBuilder(diContext.diBuilder)
        bindings.disposeDIBuilder(diContext.diBuilder)

        if let int32Type = bindings.int32Type(context: context),
           let debugVersionConst = bindings.constInt(int32Type, value: 3),
           let debugVersionMD = bindings.valueAsMetadata(debugVersionConst)
        {
            bindings.addModuleFlag(llvmModule, behavior: 1, key: "Debug Info Version", value: debugVersionMD)
        }

        if let int32Type = bindings.int32Type(context: context),
           let dwarfVersionConst = bindings.constInt(int32Type, value: 5),
           let dwarfVersionMD = bindings.valueAsMetadata(dwarfVersionConst)
        {
            bindings.addModuleFlag(llvmModule, behavior: 1, key: "Dwarf Version", value: dwarfVersionMD)
        }
    }

    func defineWeakFrameRuntimeStubs(
        module: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) throws {
        _ = try defineWeakRuntimeFunction(
            named: "kk_register_frame_map",
            argumentCount: 2,
            module: module,
            context: context,
            int64Type: int64Type
        )
        _ = try defineWeakRuntimeFunction(
            named: "kk_push_frame",
            argumentCount: 2,
            module: module,
            context: context,
            int64Type: int64Type
        )
        _ = try defineWeakRuntimeFunction(
            named: "kk_pop_frame",
            argumentCount: 0,
            module: module,
            context: context,
            int64Type: int64Type
        )
    }

    func defineWeakRuntimeFunction(
        named name: String,
        argumentCount: Int,
        module: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) throws -> LLVMFunction {
        let parameterTypes = Array(repeating: int64Type, count: max(0, argumentCount))
        guard let functionType = bindings.functionType(
            returnType: int64Type,
            parameters: parameterTypes,
            isVarArg: false
        ) else {
            throw LLVMBackendError.nativeEmissionFailed("failed to create runtime function type for '\(name)'")
        }
        guard let functionValue = bindings.getNamedFunction(module: module, name: name)
            ?? bindings.addFunction(module: module, name: name, functionType: functionType)
        else {
            throw LLVMBackendError.nativeEmissionFailed("failed to define weak runtime stub '\(name)'")
        }
        bindings.setWeakAnyLinkage(functionValue)

        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMBackendError.nativeEmissionFailed("failed to create builder for runtime stub '\(name)'")
        }
        defer { bindings.disposeBuilder(builder) }

        guard let entry = bindings.appendBasicBlock(context: context, function: functionValue, name: "entry") else {
            throw LLVMBackendError.nativeEmissionFailed("failed to create runtime stub block for '\(name)'")
        }
        bindings.positionBuilder(builder, at: entry)
        let zero = bindings.constInt(int64Type, value: 0) ?? bindings.getUndef(type: int64Type)
        _ = bindings.buildRet(builder, value: zero)
        return LLVMFunction(value: functionValue, type: functionType)
    }

    func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }
}
