#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1083: the kotlin.concurrent nominal and factory surface is source-backed
/// while the follow-up constructor/member migrations retain their residual links.
@Suite(.serialized)
struct AtomicTopLevelSourceTests {
    private static nonisolated(unsafe) var shared: (CompilationContext, SemaModule, StringInterner)?

    private func sharedSema() throws -> (CompilationContext, SemaModule, StringInterner) {
        if let shared = Self.shared {
            return shared
        }
        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (ctx, try #require(ctx.sema), ctx.interner)
        }
        let shared = try #require(result)
        Self.shared = shared
        return shared
    }

    private func symbol(
        named name: String,
        in package: [String],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        let fqName = package.map(interner.intern) + [interner.intern(name)]
        return try #require(
            sema.symbols.lookup(fqName: fqName),
            Comment(rawValue: "Missing " + package.joined(separator: ".") + "." + name)
        )
    }

    @Test
    func testAtomicNominalsAndFactoriesAreSourceBacked() throws {
        let (ctx, sema, interner) = try sharedSema()
        let package = ["kotlin", "concurrent"]
        let sourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/concurrent/Stdlib.kt")
        let nominalNames = [
            "AtomicArray",
            "AtomicInt",
            "AtomicIntArray",
            "AtomicLong",
            "AtomicLongArray",
            "AtomicNativePtr",
            "AtomicReference",
        ]
        for name in nominalNames {
            let nominal = try symbol(named: name, in: package, sema: sema, interner: interner)
            let info = try #require(sema.symbols.symbol(nominal))
            #expect(info.kind == .class)
            #expect(!info.flags.contains(.synthetic), Comment(rawValue: name + " must not remain synthetic"))
            #expect(sema.symbols.isSourceBackedSymbol(nominal), Comment(rawValue: name + " must be source-backed"))
            #expect(sema.symbols.sourceFileID(for: nominal) == sourceFileID)
            #expect(info.declSite != nil)
        }

        for name in ["AtomicArray", "AtomicIntArray", "AtomicLongArray"] {
            let factoryCandidates = sema.symbols.lookupAll(
                fqName: package.map(interner.intern) + [interner.intern(name)]
            ).filter { candidate in
                guard let info = sema.symbols.symbol(candidate),
                      info.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.parameterTypes.count == 2
            }
            let factory = try #require(
                factoryCandidates.first,
                Comment(rawValue: "Missing " + name + "(Int, init) factory")
            )
            #expect(
                sema.symbols.isSourceBackedSymbol(factory),
                Comment(rawValue: name + "(Int, init) must be source-backed")
            )
            #expect(!sema.symbols.symbol(factory)!.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: factory) == nil)
        }
    }

    @Test
    func testResidualAtomicLinksReuseGenericClassTypeParameter() throws {
        let (_, sema, interner) = try sharedSema()
        let package = ["kotlin", "concurrent"].map(interner.intern)
        let classFQName = package + [interner.intern("AtomicReference")]
        let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
        let classTypeParameter = try #require(
            sema.types.nominalTypeParameterSymbols(for: classSymbol).first
        )

        let load = try #require(
            sema.symbols.lookupAll(fqName: classFQName + [interner.intern("load")]).first,
            "Missing residual AtomicReference.load"
        )
        let loadInfo = try #require(sema.symbols.symbol(load))
        let loadSignature = try #require(sema.symbols.functionSignature(for: load))
        #expect(loadInfo.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: load) == "__kk_atomic_ref_load")
        #expect(loadSignature.typeParameterSymbols == [classTypeParameter])
        guard case let .typeParam(returnType) = sema.types.kind(of: loadSignature.returnType) else {
            Issue.record("AtomicReference.load should return the class T type parameter")
            return
        }
        #expect(returnType.symbol == classTypeParameter)
    }

    @Test
    func testResidualScalarConstructorKeepsRuntimeLink() throws {
        let (_, sema, interner) = try sharedSema()
        let classFQName = ["kotlin", "concurrent", "AtomicInt"].map(interner.intern)
        let constructor = try #require(
            sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first {
                guard let signature = sema.symbols.functionSignature(for: $0) else { return false }
                return signature.parameterTypes == [sema.types.intType]
            },
            "Missing residual AtomicInt(Int) constructor"
        )
        let info = try #require(sema.symbols.symbol(constructor))
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: constructor) == "kk_atomic_int_create")
    }

    @Test
    func testResidualArrayConstructorKeepsRuntimeLink() throws {
        let (_, sema, interner) = try sharedSema()
        let classFQName = ["kotlin", "concurrent", "AtomicIntArray"].map(interner.intern)
        let constructor = try #require(
            sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first {
                guard let signature = sema.symbols.functionSignature(for: $0) else { return false }
                return signature.parameterTypes == [sema.types.intType]
            },
            "Missing residual AtomicIntArray(Int) constructor"
        )
        let info = try #require(sema.symbols.symbol(constructor))
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: constructor) == "kk_atomic_int_array_create")
    }

    @Test
    func testAtomicArraySizePropertyCoexistsWithFactoryParameter() throws {
        let (_, sema, interner) = try sharedSema()
        let package = ["kotlin", "concurrent"].map(interner.intern)
        for name in ["AtomicIntArray", "AtomicLongArray"] {
            let classFQName = package + [interner.intern(name)]
            let sizeFQName = classFQName + [interner.intern("size")]
            let symbols = sema.symbols.lookupAll(fqName: sizeFQName)
            let propertySymbol = symbols.first { sema.symbols.symbol($0)?.kind == .property }
            let requiredProperty = try #require(
                propertySymbol,
                Comment(rawValue: name + ".size property must coexist with " + name + "(size: Int, init) parameter")
            )
            #expect(sema.symbols.propertyType(for: requiredProperty) == sema.types.intType)
            let factoryCandidates = sema.symbols.lookupAll(fqName: classFQName).filter { candidate in
                guard let info = sema.symbols.symbol(candidate),
                      info.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.parameterTypes.count == 2
            }
            let factory = try #require(
                factoryCandidates.first,
                Comment(rawValue: "Missing " + name + "(Int, init) factory")
            )
            let factorySignature = try #require(sema.symbols.functionSignature(for: factory))
            let firstParamSymbol = try #require(factorySignature.valueParameterSymbols.first)
            let firstParam = try #require(sema.symbols.symbol(firstParamSymbol))
            #expect(firstParam.kind == .valueParameter)
            #expect(firstParam.name == interner.intern("size"))
        }
    }

    @Test
    func testResidualArraySizePropertyKeepsRuntimeLink() throws {
        let (_, sema, interner) = try sharedSema()
        let cases: [(name: String, link: String)] = [
            ("AtomicIntArray", "kk_atomic_int_array_size"),
            ("AtomicLongArray", "kk_atomic_long_array_size"),
        ]
        for item in cases {
            let classFQName = ["kotlin", "concurrent", item.name].map(interner.intern)
            let size = try #require(
                sema.symbols.lookupAll(fqName: classFQName + [interner.intern("size")]).first {
                    sema.symbols.symbol($0)?.kind == .property
                },
                Comment(rawValue: "Missing residual " + item.name + ".size")
            )
            let info = try #require(sema.symbols.symbol(size))
            #expect(info.flags.contains(.synthetic), Comment(rawValue: item.name + ".size must stay residual"))
            #expect(sema.symbols.externalLinkName(for: size) == item.link)
            #expect(sema.symbols.propertyType(for: size) == sema.types.intType)
        }
    }
}
#endif
