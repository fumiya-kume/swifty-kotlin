@testable import CompilerCore
import Testing

extension BundledSyntheticOverlapDiagnosticTests {
    @Test(arguments: ["source", "imported", "otherOwner", "otherPackage", "syntheticOnly"])
    func mutableCollectionOverlapRequiresMatchingSourceExtension(variant: String) {
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let package = ["kotlin", "collections"].map(interner.intern)
        let ownerFQName = package + [interner.intern("MutableCollection")]
        let owner = symbols.define(
            kind: .interface, name: interner.intern("MutableCollection"), fqName: ownerFQName,
            declSite: nil, visibility: .public
        )
        let receiver = types.make(.classType(ClassType(classSymbol: owner)))
        let name = interner.intern("remove")
        let stub = symbols.define(
            kind: .function, name: name, fqName: ownerFQName + [name],
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(owner, for: stub)
        symbols.setFunctionSignature(
            FunctionSignature(receiverType: receiver, parameterTypes: [types.anyType], returnType: types.booleanType),
            for: stub
        )

        let extensionPackage = variant == "otherPackage" ? [interner.intern("other")] : package
        let flags: SymbolFlags = switch variant {
        case "imported": [.synthetic, .importedLibrary]
        case "syntheticOnly": [.synthetic]
        default: []
        }
        let source = symbols.define(
            kind: .function, name: name, fqName: extensionPackage + [name],
            declSite: variant == "imported" ? nil : makeRange(), visibility: .public, flags: flags
        )
        var extensionReceiver = receiver
        if variant == "otherOwner" {
            let other = symbols.define(
                kind: .interface, name: interner.intern("OtherCollection"),
                fqName: package + [interner.intern("OtherCollection")], declSite: nil, visibility: .public
            )
            extensionReceiver = types.make(.classType(ClassType(classSymbol: other)))
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: extensionReceiver, parameterTypes: [types.anyType], returnType: types.booleanType
            ),
            for: source
        )

        var index = BundledDeclarationIndex.empty
        index.insert(BundledMemberKey(ownerFQName: ownerFQName, name: name, arity: 1))
        index.warnSyntheticOverlaps(symbols: symbols, types: types, diagnostics: diagnostics, interner: interner)

        let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(warnings.count == (["source", "imported"].contains(variant) ? 0 : 1))
        for warning in warnings {
            #expect(warning.severity == .warning)
            #expect(warning.message.contains("'remove' on 'kotlin.collections.MutableCollection' (arity 1)"))
        }
    }
}
