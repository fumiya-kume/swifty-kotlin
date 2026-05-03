import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: withWorker(name, errorReporting, block) top-level function.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - withWorker

    func registerNativeConcurrentWithWorker(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("withWorker")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("R")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let blockType = types.make(.functionType(FunctionType(
            receiver: workerType,
            params: [],
            returnType: typeParameterType
        )))

        registerNativeConcurrentPackageFunction(
            named: "withWorker",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: typeParameterType,
            parameters: [
                (name: "name", type: types.makeNullable(types.stringType)),
                (name: "errorReporting", type: types.booleanType),
                (name: "block", type: blockType),
            ],
            defaultValues: [true, true, false],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
    }
}
