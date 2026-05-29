@testable import CompilerCore
import XCTest

/// STDLIB-UUID-FN-002: Validates ByteBuffer.putUuid(...) extension overloads.
final class ByteBufferPutUuidFunctionTests: XCTestCase {
    func testByteBufferPutUuidSyntheticFunctionsAreRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let kotlinUuidPkg = ["kotlin", "uuid"].map { interner.intern($0) }
        let byteBufferSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("nio"),
            interner.intern("ByteBuffer"),
        ]))
        let uuidSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinUuidPkg + [interner.intern("Uuid")]))
        let byteBufferType = sema.types.make(.classType(ClassType(
            classSymbol: byteBufferSymbol,
            args: [],
            nullability: .nonNull
        )))
        let uuidType = sema.types.make(.classType(ClassType(
            classSymbol: uuidSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functions = sema.symbols.lookupAll(fqName: kotlinUuidPkg + [interner.intern("putUuid")])

        func putUuid(linkName: String, parameterTypes: [TypeID]) throws -> SymbolID {
            try XCTUnwrap(
                functions.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return sema.symbols.externalLinkName(for: symbolID) == linkName
                        && signature.receiverType == byteBufferType
                        && signature.parameterTypes == parameterTypes
                        && signature.returnType == byteBufferType
                },
                "ByteBuffer.putUuid overload \(linkName) must be registered"
            )
        }

        let putCurrent = try putUuid(linkName: "kk_byte_buffer_put_uuid", parameterTypes: [uuidType])
        let putAtIndex = try putUuid(
            linkName: "kk_byte_buffer_put_uuid_at",
            parameterTypes: [sema.types.intType, uuidType]
        )

        for symbol in [putCurrent, putAtIndex] {
            XCTAssertTrue(sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true)
            let annotations = sema.symbols.annotations(for: symbol)
            XCTAssertTrue(annotations.contains { $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi" })
            XCTAssertTrue(annotations.contains { $0.annotationFQName == "kotlin.IgnorableReturnValue" })
        }
    }

    func testByteBufferPutUuidResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.nio.ByteBuffer
        import kotlin.OptIn
        import kotlin.uuid.ExperimentalUuidApi
        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid

        @OptIn(ExperimentalUuidApi::class)
        fun write(buffer: ByteBuffer, uuid: Uuid): ByteBuffer {
            return buffer.putUuid(uuid)
        }

        @OptIn(ExperimentalUuidApi::class)
        fun writeAt(buffer: ByteBuffer, uuid: Uuid): ByteBuffer {
            return buffer.putUuid(4, uuid)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteBuffer.putUuid overloads to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
