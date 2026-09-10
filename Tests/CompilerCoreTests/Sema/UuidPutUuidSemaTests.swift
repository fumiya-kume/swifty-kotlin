@testable import CompilerCore
import Foundation
import Testing

// MARK: - KSP-508: java.nio.ByteBuffer.putUuid / java.nio.ByteBuffer.putUuid(index, uuid) sema wiring
//
// Both extension functions are pure Kotlin, declared in Stdlib/kotlin/uuid/Uuid.kt
// (no externalLinkName of their own). Verify they are source-backed with the
// expected ByteBuffer receiver, parameter/return types, and @ExperimentalUuidApi
// opt-in annotations.

@Suite(.serialized)
struct UuidPutUuidSemaTests {

    // MARK: - Shared fixture

    private static nonisolated(unsafe) var _sharedSema: (CompilationContext, SemaModule, StringInterner)?

    private func sharedSemaWithContext() throws -> (CompilationContext, SemaModule, StringInterner) {
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

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        let (_, sema, interner) = try sharedSemaWithContext()
        return (sema, interner)
    }

    private func byteBufferSymbol(sema: SemaModule, interner: StringInterner) -> SymbolID? {
        let fq = ["java", "nio", "ByteBuffer"].map { interner.intern($0) }
        return sema.symbols.lookup(fqName: fq)
    }

    /// Finds the `putUuid` symbol with a ByteBuffer receiver and `parameterCount` value parameters.
    private func findPutUuidSymbol(
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let interned = ["kotlin", "uuid", "putUuid"].map { interner.intern($0) }
        let byteBufferSym = byteBufferSymbol(sema: sema, interner: interner)
        return sema.symbols.lookupAll(fqName: interned).first { sym in
            guard let sig = sema.symbols.functionSignature(for: sym),
                  let receiverType = sig.receiverType,
                  sig.parameterTypes.count == parameterCount
            else { return false }
            guard case .classType(let ct) = sema.types.kind(of: receiverType) else { return false }
            return byteBufferSym == nil ? false : ct.classSymbol == byteBufferSym
        }
    }

    private func isSourceBacked(
        sym: SymbolID,
        ctx: CompilationContext,
        sema: SemaModule
    ) -> Bool {
        let uuidSourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        guard let info = sema.symbols.symbol(sym) else { return false }
        return !info.flags.contains(.synthetic) && sema.symbols.sourceFileID(for: sym) == uuidSourceFileID
    }

    // MARK: - putUuid(index, uuid) overload

    @Test
    func testPutUuidExtensionFunctionIsSourceBacked() throws {
        let (ctx, sema, interner) = try sharedSemaWithContext()
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner)
        )
        #expect(
            isSourceBacked(sym: sym, ctx: ctx, sema: sema),
            "ByteBuffer.putUuid(index, uuid) must be declared in Uuid.kt, not registered as a synthetic stub"
        )
    }

    @Test
    func testPutUuidHasByteBufferReceiver() throws {
        let (sema, interner) = try sharedSema()
        let byteBufferSym = try #require(
            byteBufferSymbol(sema: sema, interner: interner),
            "java.nio.ByteBuffer must be registered"
        )
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner),
            "ByteBuffer.putUuid(index, uuid) extension function must be registered with ByteBuffer receiver"
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        let receiverType = try #require(sig.receiverType)
        guard case .classType(let ct) = sema.types.kind(of: receiverType) else {
            Issue.record("putUuid receiver must be a class type"); return
        }
        #expect(ct.classSymbol == byteBufferSym, "putUuid receiver must be java.nio.ByteBuffer")
    }

    @Test
    func testPutUuidHasTwoParameters() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner)
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(sig.parameterTypes.count == 2, "putUuid(index, uuid) must take exactly 2 parameters")
    }

    @Test
    func testPutUuidFirstParameterIsInt() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner)
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(sig.parameterTypes[0] == sema.types.intType, "putUuid first parameter (index) must be Int")
    }

    @Test
    func testPutUuidSecondParameterIsUuid() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner)
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: sig.parameterTypes[1]) else {
            Issue.record("putUuid second parameter must be a class type"); return
        }
        #expect(ct.classSymbol == uuidSym, "putUuid second parameter (uuid) must be kotlin.uuid.Uuid")
    }

    @Test
    func testPutUuidReturnsByteBuffer() throws {
        let (sema, interner) = try sharedSema()
        let byteBufferSym = try #require(byteBufferSymbol(sema: sema, interner: interner))
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner)
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            Issue.record("putUuid return type must be a class type"); return
        }
        #expect(ct.classSymbol == byteBufferSym, "putUuid must return java.nio.ByteBuffer")
    }

    // MARK: - putUuid(uuid) single-parameter overload

    @Test
    func testPutUuidSingleOverloadIsSourceBacked() throws {
        let (ctx, sema, interner) = try sharedSemaWithContext()
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 1, sema: sema, interner: interner)
        )
        #expect(
            isSourceBacked(sym: sym, ctx: ctx, sema: sema),
            "ByteBuffer.putUuid(uuid) must be declared in Uuid.kt"
        )
    }

    @Test
    func testPutUuidSingleOverloadHasOneUuidParameter() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findPutUuidSymbol(parameterCount: 1, sema: sema, interner: interner)
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(sig.parameterTypes.count == 1, "putUuid(uuid) must take exactly 1 parameter")

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.parameterTypes[0]) else {
            Issue.record("putUuid(uuid) parameter must be a class type"); return
        }
        #expect(ct.classSymbol == uuidSym, "putUuid(uuid) parameter must be kotlin.uuid.Uuid")
    }

    // MARK: - @ExperimentalUuidApi annotation

    @Test
    func testPutUuidIsTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try sharedSema()
        let interned = ["kotlin", "uuid", "putUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: interned)
        #expect(!syms.isEmpty, "putUuid must be registered")
        #expect(
            syms.contains { sym in
                sema.symbols.annotations(for: sym).contains {
                    $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
                }
            },
            "ByteBuffer.putUuid must carry @ExperimentalUuidApi"
        )
    }

    // MARK: - Both overloads distinct

    @Test
    func testPutUuidOverloadsAreDistinctSymbols() throws {
        let (sema, interner) = try sharedSema()
        let single = try #require(
            findPutUuidSymbol(parameterCount: 1, sema: sema, interner: interner)
        )
        let indexed = try #require(
            findPutUuidSymbol(parameterCount: 2, sema: sema, interner: interner)
        )
        #expect(single != indexed, "putUuid(uuid) and putUuid(index, uuid) must be distinct symbols")
    }
}
