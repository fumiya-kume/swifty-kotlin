#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testNativeOsFamilyUsesSourceOrderAndGeneratedEnumAPIs() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.OsFamily

        fun main() {
            println(OsFamily.entries.size)
            println(OsFamily.values().size)
            println(OsFamily.valueOf("TVOS"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "OsFamily enum APIs should lower without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let osFamilyFQName = [
                interner.intern("kotlin"),
                interner.intern("native"),
                interner.intern("OsFamily"),
            ]
            let osFamilySymbol = try #require(sema.symbols.lookup(fqName: osFamilyFQName))
            #expect(sema.symbols.symbol(osFamilySymbol)?.kind == .enumClass)
            #expect(sema.symbols.isSourceBackedSymbol(osFamilySymbol))
            #expect(
                sema.symbols.annotations(for: osFamilySymbol).contains {
                    $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                }
            )

            let entryNames = sema.symbols.children(ofFQName: osFamilyFQName)
                .compactMap { symbolID -> SemanticSymbol? in
                    guard let symbol = sema.symbols.symbol(symbolID), symbol.kind == .field else {
                        return nil
                    }
                    return symbol
                }
                .sorted { $0.id.rawValue < $1.id.rawValue }
                .map { interner.resolve($0.name) }
            let expectedEntryNames = [
                "UNKNOWN", "MACOSX", "IOS", "LINUX", "WINDOWS",
                "ANDROID", "WASM", "TVOS", "WATCHOS",
            ]
            #expect(
                entryNames == expectedEntryNames,
                "OsFamily entries must retain Kotlin 2.3.10 source order"
            )

            let valuesSymbol = try #require(
                sema.symbols.lookup(fqName: osFamilyFQName + [interner.intern("values")])
            )
            #expect(sema.symbols.symbol(valuesSymbol)?.kind == .function)
            #expect(sema.symbols.functionSignature(for: valuesSymbol)?.parameterTypes.isEmpty == true)

            let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: osFamilySymbol))
            let companionFQName = try #require(sema.symbols.symbol(companionSymbol)?.fqName)
            let valueOfSymbol = try #require(
                sema.symbols.lookup(fqName: companionFQName + [interner.intern("valueOf")])
            )
            #expect(sema.symbols.symbol(valueOfSymbol)?.kind == .function)
            #expect(sema.symbols.functionSignature(for: valueOfSymbol)?.parameterTypes.count == 1)

            let entriesSymbol = try #require(
                sema.symbols.lookup(fqName: companionFQName + [interner.intern("entries")])
            )
            #expect(sema.symbols.symbol(entriesSymbol)?.kind == .property)

            let module = try #require(ctx.kir)
            let classSuffix = NameMangler.enumClassNameSuffix(for: osFamilyFQName, interner: interner)
            for (expectedOrdinal, entryName) in expectedEntryNames.enumerated() {
                let ordinalFunction = try findKIRFunction(
                    named: "\(entryName)$enumOrdinal$\(classSuffix)",
                    in: module,
                    interner: interner
                )
                let ordinalConstants = ordinalFunction.body.compactMap { instruction -> Int64? in
                    guard case let .constValue(_, .intLiteral(value)) = instruction else {
                        return nil
                    }
                    return value
                }
                #expect(
                    ordinalConstants.contains(Int64(expectedOrdinal)),
                    "\(entryName) must retain ordinal \(expectedOrdinal): \(ordinalConstants)"
                )
            }
            #expect(
                module.arena.declarations.contains { declaration in
                    guard case let .nominalType(nominal) = declaration else { return false }
                    return nominal.symbol == osFamilySymbol
                },
                "OsFamily must retain its source-backed nominal identity in KIR"
            )
        }
    }

    @Test
    func testNativeOsFamilyNominalIsRetainedForPlatformPropertyType() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun main() {
            val osFamily = Platform.osFamily
            println(osFamily)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Platform.osFamily should lower without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let osFamilyFQName = [
                interner.intern("kotlin"),
                interner.intern("native"),
                interner.intern("OsFamily"),
            ]
            let osFamilySymbol = try #require(sema.symbols.lookup(fqName: osFamilyFQName))
            #expect(sema.symbols.isSourceBackedSymbol(osFamilySymbol))

            let module = try #require(ctx.kir)
            #expect(
                module.arena.declarations.contains { declaration in
                    guard case let .nominalType(nominal) = declaration else { return false }
                    return nominal.symbol == osFamilySymbol
                },
                "Platform.osFamily must retain the source-backed OsFamily nominal in consumer KIR"
            )
        }
    }
}
#endif
