#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1198: the Kotlin/Native CpuArchitecture enum is source-backed and
/// exposes its constructor property plus generated enum APIs.
@Suite
struct NativeCpuArchitectureSourceAPITests {
    @Test
    func testCpuArchitectureSourceBackedSurfaceHasExactAPIs() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.CpuArchitecture

        fun entries(): kotlin.enums.EnumEntries<CpuArchitecture> = CpuArchitecture.entries
        fun bitness(): Int = CpuArchitecture.ARM64.bitness
        fun valueOf(): CpuArchitecture = CpuArchitecture.valueOf("WASM32")
        fun values(): Array<CpuArchitecture> = CpuArchitecture.values()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cpuArchitectureFQName = ["kotlin", "native", "CpuArchitecture"].map { interner.intern($0) }
        let cpuArchitectureSymbol = try #require(
            sema.symbols.lookup(fqName: cpuArchitectureFQName)
        )
        let cpuArchitecture = try #require(sema.symbols.symbol(cpuArchitectureSymbol))
        #expect(cpuArchitecture.kind == .enumClass)
        #expect(sema.symbols.isSourceBackedSymbol(cpuArchitectureSymbol))
        #expect(!cpuArchitecture.flags.contains(.synthetic))

        let expectedEntries = ["UNKNOWN", "ARM32", "ARM64", "X86", "X64", "MIPS32", "MIPSEL32", "WASM32"]
        let entryNames = sema.symbols.children(ofFQName: cpuArchitectureFQName)
            .compactMap { symbolID -> SemanticSymbol? in
                guard let symbol = sema.symbols.symbol(symbolID), symbol.kind == .field else {
                    return nil
                }
                return symbol
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { interner.resolve($0.name) }
        #expect(entryNames == expectedEntries)

        let bitnessSymbol = try #require(
            sema.symbols.lookup(fqName: cpuArchitectureFQName + [interner.intern("bitness")])
        )
        #expect(sema.symbols.symbol(bitnessSymbol)?.kind == .property)
        #expect(sema.symbols.isSourceBackedSymbol(bitnessSymbol))
        #expect(sema.symbols.propertyType(for: bitnessSymbol) == sema.types.intType)

        let valuesSymbol = try #require(
            sema.symbols.lookup(fqName: cpuArchitectureFQName + [interner.intern("values")])
        )
        #expect(sema.symbols.symbol(valuesSymbol)?.kind == .function)
        #expect(sema.symbols.functionSignature(for: valuesSymbol)?.parameterTypes.isEmpty == true)

        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: cpuArchitectureSymbol))
        let companionFQName = try #require(sema.symbols.symbol(companionSymbol)?.fqName)
        let entriesSymbol = try #require(
            sema.symbols.lookup(fqName: companionFQName + [interner.intern("entries")])
        )
        #expect(sema.symbols.symbol(entriesSymbol)?.kind == .property)
        let valueOfSymbol = try #require(
            sema.symbols.lookup(fqName: companionFQName + [interner.intern("valueOf")])
        )
        #expect(sema.symbols.symbol(valueOfSymbol)?.kind == .function)
        #expect(sema.symbols.functionSignature(for: valueOfSymbol)?.parameterTypes == [sema.types.stringType])
        #expect(sema.symbols.functionSignature(for: valueOfSymbol)?.returnType == sema.types.make(.classType(ClassType(
            classSymbol: cpuArchitectureSymbol,
            args: [],
            nullability: .nonNull
        ))))
    }
}
#endif
