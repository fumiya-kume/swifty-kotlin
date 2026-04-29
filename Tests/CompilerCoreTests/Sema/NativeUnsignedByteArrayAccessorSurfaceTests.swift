@testable import CompilerCore
import Foundation
import XCTest

final class NativeUnsignedByteArrayAccessorSurfaceTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func byteArrayType(
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let fqName = ["kotlin", "ByteArray"].map { interner.intern($0) }
        let byteArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.ByteArray must be registered",
            file: file,
            line: line
        )
        return sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func nativeAccessorSignature(
        named name: String,
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let nativeFQName = ["kotlin", "native", name].map { interner.intern($0) }
        let receiverType = try byteArrayType(sema: sema, interner: interner, file: file, line: line)
        let candidates = sema.symbols.lookupAll(fqName: nativeFQName)
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiverType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        XCTFail("Expected kotlin.native.\(name) ByteArray accessor, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testUnsignedByteArrayAccessorsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let expected: [(name: String, returnType: TypeID, linkName: String)] = [
            ("getUByteAt", sema.types.ubyteType, "kk_native_byteArray_getUByteAt"),
            ("getUShortAt", sema.types.ushortType, "kk_native_byteArray_getUShortAt"),
            ("getUIntAt", sema.types.uintType, "kk_native_byteArray_getUIntAt"),
            ("getULongAt", sema.types.ulongType, "kk_native_byteArray_getULongAt"),
        ]

        for accessor in expected {
            let (symbol, signature) = try nativeAccessorSignature(
                named: accessor.name,
                returnType: accessor.returnType,
                sema: sema,
                interner: interner
            )
            let annotations = sema.symbols.annotations(for: symbol)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), accessor.linkName)
            XCTAssertTrue(
                annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi" },
                "\(accessor.name) must carry ExperimentalNativeApi metadata"
            )
            XCTAssertTrue(
                annotations.contains { $0.annotationFQName == "kotlin.ExperimentalUnsignedTypes" },
                "\(accessor.name) must carry ExperimentalUnsignedTypes metadata"
            )
        }
    }

    func testUnsignedByteArrayAccessorsResolveInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
        import kotlin.native.getUByteAt
        import kotlin.native.getUShortAt
        import kotlin.native.getUIntAt
        import kotlin.native.getULongAt

        fun probeUByte(bytes: ByteArray): UByte = bytes.getUByteAt(0)
        fun probeUShort(bytes: ByteArray): UShort = bytes.getUShortAt(1)
        fun probeUInt(bytes: ByteArray): UInt = bytes.getUIntAt(2)
        fun probeULong(bytes: ByteArray): ULong = bytes.getULongAt(0)
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected unsigned ByteArray accessors to resolve without errors, got \(errors)")
    }
}
