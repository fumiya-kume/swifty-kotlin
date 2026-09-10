@testable import CompilerCore
import Foundation
import Testing

// MARK: - KSP-310: kotlin.uuid.Uuid API surface inventory

@Suite(.serialized)
struct UuidAPISurfaceInventoryTests {
    private static nonisolated(unsafe) var _sharedSema: (CompilationContext, SemaModule, StringInterner)?

    private func sharedSema() throws -> (CompilationContext, SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (ctx, sema, ctx.interner)
        }
        let triple = try #require(result)
        Self._sharedSema = triple
        return triple
    }

    private func symbols(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: fqPath.map { interner.intern($0) })
    }

    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        Set(symbols(fqPath: fqPath, sema: sema, interner: interner).compactMap {
            sema.symbols.externalLinkName(for: $0)
        })
    }

    @Test
    func testUuidPackageClassAndCompanionAreBundledFromSource() throws {
        let (ctx, sema, interner) = try sharedSema()
        let uuidSourceFileID = try #require(ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt"))

        let packageSymbol = sema.symbols.lookup(fqName: ["kotlin", "uuid"].map { interner.intern($0) })
        #expect(packageSymbol != nil, "kotlin.uuid package must be present")

        let uuidSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "uuid", "Uuid"].map {
            interner.intern($0)
        }))
        let uuidInfo = try #require(sema.symbols.symbol(uuidSymbol))
        #expect(uuidInfo.kind == .class)
        #expect(sema.symbols.sourceFileID(for: uuidSymbol) == uuidSourceFileID)

        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: uuidSymbol))
        let companionInfo = try #require(sema.symbols.symbol(companionSymbol))
        #expect(companionInfo.kind == .object)
        #expect(!companionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.sourceFileID(for: companionSymbol) == uuidSourceFileID)
    }

    @Test
    func testJavaUuidShellIsSourceBackedWithJavaConstructorShape() throws {
        let (ctx, sema, interner) = try sharedSema()
        let javaUuidSourceFileID = try #require(
            ctx.sourceManager.fileID(forPath: "__bundled_java/util/UUID.kt")
        )
        let javaUuidPath = ["java", "util", "UUID"]
        let javaUuidSymbol = try #require(
            sema.symbols.lookup(fqName: javaUuidPath.map { interner.intern($0) })
        )
        let javaUuidInfo = try #require(sema.symbols.symbol(javaUuidSymbol))
        #expect(javaUuidInfo.kind == .class)
        #expect(!javaUuidInfo.flags.contains(.synthetic), "java.util.UUID must be source-backed")
        #expect(sema.symbols.sourceFileID(for: javaUuidSymbol) == javaUuidSourceFileID)

        let constructorPath = javaUuidPath + ["<init>"]
        let constructors = sema.symbols.lookupAll(fqName: constructorPath.map { interner.intern($0) })
            .filter { sema.symbols.symbol($0)?.kind == .constructor }
        let constructor = try #require(constructors.first, "java.util.UUID constructor must exist")
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(!constructorInfo.flags.contains(.synthetic))
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(signature.parameterTypes == [sema.types.longType, sema.types.longType])
        #expect(
            signature.returnType == sema.types.make(.classType(ClassType(
                classSymbol: javaUuidSymbol,
                args: [],
                nullability: .nonNull
            )))
        )
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
    }

    @Test
    func testUuidPublicClassApisAreSourceBackedWithoutPureRuntimeLinks() throws {
        let (ctx, sema, interner) = try sharedSema()
        let uuidSourceFileID = try #require(ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt"))
        let publicApiPaths: [[String]] = [
            ["kotlin", "uuid", "Uuid", "Companion", "SIZE_BITS"],
            ["kotlin", "uuid", "Uuid", "Companion", "SIZE_BYTES"],
            ["kotlin", "uuid", "Uuid", "Companion", "NIL"],
            ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"],
            ["kotlin", "uuid", "Uuid", "Companion", "random"],
            ["kotlin", "uuid", "Uuid", "Companion", "parse"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHex"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromULongs"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromUByteArray"],
            ["kotlin", "uuid", "Uuid", "Companion", "generateV4"],
            ["kotlin", "uuid", "Uuid", "mostSignificantBits"],
            ["kotlin", "uuid", "Uuid", "leastSignificantBits"],
            ["kotlin", "uuid", "Uuid", "toString"],
            ["kotlin", "uuid", "Uuid", "toHexString"],
            ["kotlin", "uuid", "Uuid", "toHexDashString"],
            ["kotlin", "uuid", "Uuid", "toLongs"],
            ["kotlin", "uuid", "Uuid", "toULongs"],
            ["kotlin", "uuid", "Uuid", "toByteArray"],
            ["kotlin", "uuid", "Uuid", "toUByteArray"],
            ["kotlin", "uuid", "Uuid", "compareTo"],
            ["kotlin", "uuid", "Uuid", "equals"],
            ["kotlin", "uuid", "Uuid", "hashCode"],
            ["kotlin", "uuid", "getUuid"],
            ["kotlin", "uuid", "putUuid"],
        ]

        for path in publicApiPaths {
            let candidates = symbols(fqPath: path, sema: sema, interner: interner)
            let symbol = try #require(candidates.first, "\(path.joined(separator: ".")) must exist")
            let info = try #require(sema.symbols.symbol(symbol))
            #expect(!info.flags.contains(.synthetic), "\(path.joined(separator: ".")) must be source-backed")
            #expect(sema.symbols.sourceFileID(for: symbol) == uuidSourceFileID)
            #expect(
                allExternalLinks(fqPath: path, sema: sema, interner: interner).isEmpty,
                "\(path.joined(separator: ".")) must not retain a pure kk_uuid_* external link"
            )
        }
    }

    @Test
    func testUuidResidualPrivateBridgesUseDowngradedNames() throws {
        let (_, sema, interner) = try sharedSema()
        let bridges: [(path: [String], link: String)] = [
            (["kotlin", "uuid", "__kk_uuid_random"], "__kk_uuid_random"),
            (["kotlin", "uuid", "__kk_uuid_lexicalOrder"], "__kk_uuid_lexicalOrder"),
            (["kotlin", "uuid", "__kk_uuid_fromLongs"], "__kk_uuid_fromLongs"),
            (["kotlin", "uuid", "__kk_uuid_toKotlinUuid"], "__kk_uuid_toKotlinUuid"),
        ]

        for bridge in bridges {
            #expect(
                allExternalLinks(fqPath: bridge.path, sema: sema, interner: interner) == [bridge.link],
                "\(bridge.path.joined(separator: ".")) must link to \(bridge.link)"
            )
        }
    }

    /// KSP-508: java.util.UUID.toKotlinUuid() is a regular Kotlin function now
    /// (source-backed, no external link of its own) whose body delegates to the
    /// __kk_uuid_toKotlinUuid bridge verified above — it is the only remaining
    /// kotlin.uuid extension that needs native support (java UUID interop).
    /// java.nio.ByteBuffer.getUuid/putUuid are pure Kotlin (covered by
    /// testUuidPublicClassApisAreSourceBackedWithoutPureRuntimeLinks above).
    @Test
    func testUuidJavaInteropExtensionIsSourceBackedDelegatingToRenamedBridge() throws {
        let (ctx, sema, interner) = try sharedSema()
        let uuidSourceFileID = try #require(ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt"))
        let path = ["kotlin", "uuid", "toKotlinUuid"]

        let symbol = try #require(symbols(fqPath: path, sema: sema, interner: interner).first)
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(!info.flags.contains(.synthetic), "toKotlinUuid must be source-backed")
        #expect(sema.symbols.sourceFileID(for: symbol) == uuidSourceFileID)
        #expect(
            allExternalLinks(fqPath: path, sema: sema, interner: interner).isEmpty,
            "toKotlinUuid itself must not carry an external link; it delegates to __kk_uuid_toKotlinUuid in its body"
        )
    }

    @Test
    func testUuidFactoryAndPropertyTypesResolve() throws {
        let (_, sema, interner) = try sharedSema()
        let uuidSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "uuid", "Uuid"].map {
            interner.intern($0)
        }))
        let uuidType: TypeID = sema.types.make(.classType(ClassType(
            classSymbol: uuidSymbol,
            args: [],
            nullability: .nonNull
        )))

        let fromLongs = try #require(symbols(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            sema: sema,
            interner: interner
        ).first)
        let fromLongsSig = try #require(sema.symbols.functionSignature(for: fromLongs))
        #expect(fromLongsSig.parameterTypes == [sema.types.longType, sema.types.longType])
        #expect(fromLongsSig.returnType == uuidType)

        let msb = try #require(symbols(
            fqPath: ["kotlin", "uuid", "Uuid", "mostSignificantBits"],
            sema: sema,
            interner: interner
        ).first)
        #expect(sema.symbols.propertyType(for: msb) == sema.types.longType)

        let lsb = try #require(symbols(
            fqPath: ["kotlin", "uuid", "Uuid", "leastSignificantBits"],
            sema: sema,
            interner: interner
        ).first)
        #expect(sema.symbols.propertyType(for: lsb) == sema.types.longType)
    }
}
