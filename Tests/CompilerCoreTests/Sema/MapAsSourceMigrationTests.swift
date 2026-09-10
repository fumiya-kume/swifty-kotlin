#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MapAsSourceMigrationTests {
    @Test
    func testMapAsFamilyUsesExactBundledSourceSignatures() throws {
        let source = """
        fun use(values: Map<String?, Int?>) {
            values.asIterable()
            values.asSequence()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Map.as-family calls must type-check: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let mapFQName = ["kotlin", "collections", "Map"].map(interner.intern)
            let entryFQName = ["kotlin", "collections", "Map", "Entry"].map(interner.intern)
            let mapSymbol = try #require(sema.symbols.lookup(fqName: mapFQName))
            let entrySymbol = try #require(sema.symbols.lookup(fqName: entryFQName))

            let cases: [(name: String, returnName: String, isInline: Bool)] = [
                ("asIterable", "Iterable", true),
                ("asSequence", "Sequence", false),
            ]

            for testCase in cases {
                let fqName = ["kotlin", "collections", testCase.name].map(interner.intern)
                let candidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard sema.symbols.isSourceBackedSymbol(symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(receiverClassType) = sema.types.kind(of: receiverType)
                    else { return false }
                    return receiverClassType.classSymbol == mapSymbol
                        && signature.parameterTypes.isEmpty
                }
                let symbolID = try #require(candidates.first, "Expected bundled Map.\(testCase.name) source declaration")
                #expect(candidates.count == 1, "Expected one exact Map.\(testCase.name) source overload")

                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.visibility == .public)
                #expect(symbol.flags.contains(.synthetic) == false)
                #expect(symbol.flags.contains(.inlineFunction) == testCase.isInline)
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                let sourceFileID = try #require(sema.symbols.sourceFileID(for: symbolID))
                #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/collections/MapHOF.kt")

                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.typeParameterSymbols.count == 2)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClassType) = sema.types.kind(of: receiverType)
                else {
                    Issue.record("Map.\(testCase.name) must have a Map receiver")
                    continue
                }
                #expect(receiverClassType.classSymbol == mapSymbol)
                #expect(receiverClassType.args.count == 2)
                if receiverClassType.args.count == 2 {
                    guard case .out = receiverClassType.args[0] else {
                        Issue.record("Map.\(testCase.name) must preserve the out K receiver projection")
                        continue
                    }
                    guard case .invariant = receiverClassType.args[1] else {
                        Issue.record("Map.\(testCase.name) must preserve the V receiver argument")
                        continue
                    }
                }

                guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else {
                    Issue.record("Map.\(testCase.name) must return a class type")
                    continue
                }
                #expect(interner.resolve(returnSymbol.name) == testCase.returnName)
                #expect(returnClassType.args.count == 1)
                guard let elementTypeArg = returnClassType.args.first else { continue }
                let elementType: TypeID
                switch elementTypeArg {
                case let .invariant(type), let .out(type):
                    elementType = type
                case .in:
                    Issue.record("Map.\(testCase.name) must return covariant entry elements")
                    continue
                case .star:
                    Issue.record("Map.\(testCase.name) must return typed entry elements")
                    continue
                }
                guard case let .classType(elementClassType) = sema.types.kind(of: elementType) else {
                    Issue.record("Map.\(testCase.name) must return Map.Entry elements")
                    continue
                }
                #expect(elementClassType.classSymbol == entrySymbol)
                #expect(elementClassType.args.count == 2)
            }
        }
    }

    @Test
    func testMapAbstractSurfaceUsesBundledSourceAndRuntimeLinks() throws {
        let source = """
        fun use(values: Map<String, Int?>): Boolean {
            val entries: Set<Map.Entry<String, Int?>> = values.entries
            val keys: Set<String> = values.keys
            val valueCollection: Collection<Int?> = values.values
            val size: Int = values.size
            val value: Int? = values["key"]
            return values.isEmpty() && entries.isNotEmpty() && keys.isNotEmpty()
                && valueCollection.isNotEmpty() && size >= 0 && value == null
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Map's six abstract members must type-check: \(ctx.diagnostics.diagnostics)"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let mapFQName = ["kotlin", "collections", "Map"].map(interner.intern)
            let mapSymbol = try #require(sema.symbols.lookup(fqName: mapFQName))
            let mapInfo = try #require(sema.symbols.symbol(mapSymbol))
            // Keep the nominal Map anchor's metadata-free shape stable; its
            // members are the source-backed declarations under test.
            #expect(mapInfo.kind == .interface)
            #expect(!mapInfo.flags.contains(.synthetic))

            let propertyCases: [(name: String, link: String)] = [
                ("size", "kk_map_size"),
                ("keys", "__kk_map_keys"),
                ("values", "__kk_map_values"),
                ("entries", "__kk_map_entries"),
            ]
            for testCase in propertyCases {
                let fqName = mapFQName + [interner.intern(testCase.name)]
                let candidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                    return symbol.kind == .property
                        && sema.symbols.parentSymbol(for: symbolID) == mapSymbol
                        && sema.symbols.isSourceBackedSymbol(symbolID)
                }
                #expect(
                    candidates.count == 1,
                    "Expected one source-backed Map.\(testCase.name) property"
                )
                guard let propertySymbol = candidates.first,
                      let propertyInfo = sema.symbols.symbol(propertySymbol)
                else { continue }
                #expect(!propertyInfo.flags.contains(.synthetic))
                #expect(propertyInfo.flags.contains(.abstractType))
                #expect(sema.symbols.externalLinkName(for: propertySymbol) == testCase.link)
                #expect(
                    ctx.sourceManager.path(of: try #require(sema.symbols.sourceFileID(for: propertySymbol)))
                        == "__bundled_kotlin/collections/Map/Map.kt"
                )
            }

            let functionCases: [(name: String, arity: Int, link: String)] = [
                ("isEmpty", 0, "kk_map_is_empty"),
                ("get", 1, "__kk_map_get"),
            ]
            for testCase in functionCases {
                let fqName = mapFQName + [interner.intern(testCase.name)]
                let candidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID)
                    else { return false }
                    return symbol.kind == .function
                        && sema.symbols.parentSymbol(for: symbolID) == mapSymbol
                        && sema.symbols.isSourceBackedSymbol(symbolID)
                        && signature.parameterTypes.count == testCase.arity
                }
                #expect(
                    candidates.count == 1,
                    "Expected one source-backed Map.\(testCase.name) function"
                )
                guard let functionSymbol = candidates.first,
                      let functionInfo = sema.symbols.symbol(functionSymbol),
                      let signature = sema.symbols.functionSignature(for: functionSymbol)
                else { continue }
                #expect(!functionInfo.flags.contains(.synthetic))
                #expect(functionInfo.flags.contains(.abstractType))
                #expect(sema.symbols.externalLinkName(for: functionSymbol) == testCase.link)
                #expect(signature.receiverType != nil)
                #expect(
                    ctx.sourceManager.path(of: try #require(sema.symbols.sourceFileID(for: functionSymbol)))
                        == "__bundled_kotlin/collections/Map/Map.kt"
                )
                if testCase.name == "isEmpty" {
                    #expect(signature.returnType == sema.types.booleanType)
                } else {
                    #expect(sema.types.nullability(of: signature.returnType) != .nonNull)
                }
            }
        }
    }
}
#endif
