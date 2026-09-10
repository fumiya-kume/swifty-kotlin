@testable import CompilerCore
import Foundation
import Testing

// KSP-508: java.nio.ByteBuffer.getUuid() / getUuid(index: Int) are pure Kotlin,
// declared in Stdlib/kotlin/uuid/Uuid.kt (no externalLinkName of their own). Verify
// both overloads are source-backed with the expected ByteBuffer receiver,
// parameter/return signatures, and @ExperimentalUuidApi annotation.

@Suite(.serialized)
struct UuidGetUuidSemaTests {

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

    /// Finds the `getUuid` symbol with the given number of Int parameters and a ByteBuffer receiver.
    private func findGetUuidSymbol(
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let interned = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
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

    // MARK: - Registration presence

    @Test
    func testGetUuidIsRegisteredInKotlinUuidPackage() throws {
        let (sema, interner) = try sharedSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        #expect(
            !sema.symbols.lookupAll(fqName: fq).isEmpty,
            "ByteBuffer.getUuid must be registered in kotlin.uuid package"
        )
    }

    // MARK: - Source-backed, not a synthetic stub

    @Test
    func testGetUuidIsSourceBackedNotSynthetic() throws {
        let (ctx, sema, interner) = try sharedSemaWithContext()
        let uuidSourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        let sym = try #require(
            findGetUuidSymbol(parameterCount: 1, sema: sema, interner: interner)
        )
        guard let info = sema.symbols.symbol(sym) else {
            Issue.record("getUuid symbol info missing"); return
        }
        #expect(!info.flags.contains(.synthetic) && sema.symbols.sourceFileID(for: sym) == uuidSourceFileID)
    }

    // MARK: - Receiver type

    @Test
    func testGetUuidHasByteBufferReceiverType() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findGetUuidSymbol(parameterCount: 1, sema: sema, interner: interner)
        )
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        guard let receiverType = sig.receiverType else {
            Issue.record("getUuid must have a receiver type (ByteBuffer)"); return
        }
        let byteBufferFQ = ["java", "nio", "ByteBuffer"].map { interner.intern($0) }
        guard let byteBufferSym = sema.symbols.lookup(fqName: byteBufferFQ) else {
            Issue.record("java.nio.ByteBuffer class symbol missing"); return
        }
        if case .classType(let ct) = sema.types.kind(of: receiverType) {
            #expect(ct.classSymbol == byteBufferSym, "getUuid receiver must be java.nio.ByteBuffer")
        } else {
            Issue.record("getUuid receiver type is not a class type; got \(sema.types.kind(of: receiverType))")
        }
    }

    // MARK: - Parameters

    @Test
    func testGetUuidIndexOverloadHasOneIntParameter() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findGetUuidSymbol(parameterCount: 1, sema: sema, interner: interner)
        )
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "getUuid(index:) must accept exactly one parameter (index: Int)")
        #expect(sig.parameterTypes.first == sema.types.intType, "index parameter must be Int")
    }

    @Test
    func testGetUuidNoArgOverloadHasNoParameters() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findGetUuidSymbol(parameterCount: 0, sema: sema, interner: interner)
        )
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        #expect(sig.parameterTypes.isEmpty, "getUuid() must accept no parameters")
    }

    // MARK: - Return type

    @Test
    func testGetUuidReturnsUuid() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findGetUuidSymbol(parameterCount: 0, sema: sema, interner: interner)
        )
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            Issue.record("kotlin.uuid.Uuid class symbol missing"); return
        }
        if case .classType(let ct) = sema.types.kind(of: sig.returnType) {
            #expect(ct.classSymbol == uuidSym, "getUuid return type must be kotlin.uuid.Uuid")
        } else {
            Issue.record("getUuid return type is not a class type; got \(sema.types.kind(of: sig.returnType))")
        }
    }

    // MARK: - @ExperimentalUuidApi annotation

    @Test
    func testGetUuidHasExperimentalUuidApiAnnotation() throws {
        let (sema, interner) = try sharedSema()
        let sym = try #require(
            findGetUuidSymbol(parameterCount: 0, sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi" },
            "getUuid must carry @ExperimentalUuidApi annotation"
        )
    }
}
