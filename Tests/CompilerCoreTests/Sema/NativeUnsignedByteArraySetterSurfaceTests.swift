@testable import CompilerCore
import Foundation
import XCTest

final class NativeUnsignedByteArraySetterSurfaceTests: XCTestCase {
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

    private func nativeSetterSignature(
        named name: String,
        valueType: TypeID,
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
                && signature.parameterTypes == [sema.types.intType, valueType]
                && signature.returnType == sema.types.unitType
            {
                return (candidate, signature)
            }
        }

        XCTFail("Expected kotlin.native.\(name) ByteArray setter, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testUnsignedByteArraySettersAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let expected: [(name: String, valueType: TypeID, linkName: String)] = [
            ("setUByteAt", sema.types.ubyteType, "kk_native_byteArray_setUByteAt"),
            ("setUShortAt", sema.types.ushortType, "kk_native_byteArray_setUShortAt"),
            ("setUIntAt", sema.types.uintType, "kk_native_byteArray_setUIntAt"),
            ("setULongAt", sema.types.ulongType, "kk_native_byteArray_setULongAt"),
        ]

        for setter in expected {
            let (symbol, signature) = try nativeSetterSignature(
                named: setter.name,
                valueType: setter.valueType,
                sema: sema,
                interner: interner
            )
            let annotations = sema.symbols.annotations(for: symbol)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), setter.linkName)
            XCTAssertTrue(
                annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi" },
                "\(setter.name) must carry ExperimentalNativeApi metadata"
            )
            XCTAssertTrue(
                annotations.contains { $0.annotationFQName == "kotlin.ExperimentalUnsignedTypes" },
                "\(setter.name) must carry ExperimentalUnsignedTypes metadata"
            )
        }
    }

    func testUnsignedByteArraySettersResolveInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
        import kotlin.native.setUByteAt
        import kotlin.native.setUShortAt
        import kotlin.native.setUIntAt
        import kotlin.native.setULongAt

        fun probe(bytes: ByteArray, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            bytes.setUByteAt(0, ub)
            bytes.setUShortAt(1, us)
            bytes.setUIntAt(2, ui)
            bytes.setULongAt(0, ul)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected unsigned ByteArray setters to resolve without errors, got \(errors)")
    }
}
