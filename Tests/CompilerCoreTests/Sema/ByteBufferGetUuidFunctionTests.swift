@testable import CompilerCore
import XCTest

/// STDLIB-UUID-FN-001: Validates ByteBuffer.getUuid() extension overloads.
final class ByteBufferGetUuidFunctionTests: XCTestCase {
    func testByteBufferGetUuidSyntheticFunctionsAreRegistered() throws {
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
        let functions = sema.symbols.lookupAll(fqName: kotlinUuidPkg + [interner.intern("getUuid")])

        func getUuid(linkName: String, parameterTypes: [TypeID]) throws -> SymbolID {
            try XCTUnwrap(
                functions.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return sema.symbols.externalLinkName(for: symbolID) == linkName
                        && signature.receiverType == byteBufferType
                        && signature.parameterTypes == parameterTypes
                        && signature.returnType == uuidType
                },
                "ByteBuffer.getUuid overload \(linkName) must be registered"
            )
        }

        let getCurrent = try getUuid(linkName: "kk_byte_buffer_get_uuid", parameterTypes: [])
        let getAtIndex = try getUuid(linkName: "kk_byte_buffer_get_uuid_at", parameterTypes: [sema.types.intType])

        for symbol in [getCurrent, getAtIndex] {
            XCTAssertTrue(sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true)
            XCTAssertTrue(sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
            })
        }
    }

    func testByteBufferGetUuidResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.nio.ByteBuffer
        import kotlin.OptIn
        import kotlin.uuid.ExperimentalUuidApi
        import kotlin.uuid.Uuid
        import kotlin.uuid.getUuid

        @OptIn(ExperimentalUuidApi::class)
        fun read(buffer: ByteBuffer): Uuid {
            return buffer.getUuid()
        }

        @OptIn(ExperimentalUuidApi::class)
        fun readAt(buffer: ByteBuffer): Uuid {
            return buffer.getUuid(4)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteBuffer.getUuid overloads to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
