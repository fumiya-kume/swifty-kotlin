@testable import CompilerCore
import RuntimeABI
import XCTest

/// STDLIB-IO-FN-029: Validates that `InputStream.readBytes()` resolves through
/// Sema for the `java.io.InputStream` receiver and produces a `ByteArray`
/// value (modelled in the runtime as `List<Int>`).  The synthetic stub is
/// registered in `HeaderHelpers+SyntheticFileIOStubs.swift` and binds to the
/// runtime helper `kk_input_stream_readAllBytes` declared in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
///
/// The receiver is NOT closed by `readBytes()` — callers are expected to wrap
/// the call in `.use { it.readBytes() }`.  These tests pin down both the
/// stand-alone call shape and the more idiomatic `.use` pattern.
final class InputStreamReadBytesFunctionTests: XCTestCase {
    // MARK: - Basic resolution

    /// `InputStream.readBytes()` should type-check when invoked on a plain
    /// `java.io.InputStream` receiver.  The returned value must be assignable
    /// to a `ByteArray` (which the runtime models as `List<Int>`).
    func testInputStreamReadBytesResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import java.io.InputStream

        fun loadAll(file: File): ByteArray {
            val stream: InputStream = file.inputStream()
            return stream.readBytes()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// `BufferedInputStream` is a subtype of `InputStream`, so the receiver
    /// inheritance check should also let `readBytes()` resolve when the static
    /// receiver type is a buffered stream.  This exercises the inheritance
    /// path through the synthetic stub registry.
    func testBufferedInputStreamReadBytesResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.BufferedInputStream
        import java.io.File

        fun loadAll(file: File): ByteArray {
            val buffered: BufferedInputStream = file.inputStream().buffered()
            return buffered.readBytes()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected BufferedInputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// The idiomatic Kotlin usage wraps the call in `.use { }`, which both
    /// drains the stream and closes the resource.  Sema must resolve the
    /// `readBytes()` invocation inside a closure body when the receiver flows
    /// through the synthetic `Closeable.use` extension.
    func testInputStreamReadBytesInsideUseBlock() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(file: File): ByteArray {
            return file.inputStream().use { stream ->
                stream.readBytes()
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.use { it.readBytes() } to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Signature / runtime link

    /// Pin down the symbol-level invariants we expect from the synthetic
    /// `InputStream.readBytes()` stub:
    ///   - the symbol is registered under `java.io.InputStream.readBytes`
    ///   - the receiver type is `java.io.InputStream`
    ///   - there are no value parameters
    ///   - the return type is `kotlin.collections.List<Int>` (the runtime's
    ///     ByteArray representation)
    ///   - the external link name resolves to `kk_input_stream_readAllBytes`
    ///
    /// Pinning these here guards against accidental renames or signature
    /// drift that would silently break the lowering pipeline.
    func testInputStreamReadBytesSignatureAndRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let interner = ctx.interner
        let sema = try XCTUnwrap(ctx.sema)
        let symbols = sema.symbols
        let types = sema.types

        let inputStreamSymbol = try XCTUnwrap(
            symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
        )
        let inputStreamType = types.make(
            .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
        )
        let listSymbol = try XCTUnwrap(
            symbols.lookup(fqName: ["kotlin", "collections", "List"].map(interner.intern))
        )
        let listOfIntType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.intType)],
            nullability: .nonNull
        )))

        let candidates = symbols.lookupAll(
            fqName: ["java", "io", "InputStream", "readBytes"].map(interner.intern)
        )
        let readBytes = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes.isEmpty
        })

        XCTAssertEqual(
            symbols.externalLinkName(for: readBytes),
            "kk_input_stream_readAllBytes",
            "InputStream.readBytes should bind to runtime helper kk_input_stream_readAllBytes"
        )

        let signature = try XCTUnwrap(symbols.functionSignature(for: readBytes))
        XCTAssertEqual(signature.returnType, listOfIntType,
                       "InputStream.readBytes() must return ByteArray (List<Int>)")
        XCTAssertEqual(signature.receiverType, inputStreamType)
        XCTAssertTrue(signature.valueParameterIsVararg.allSatisfy { !$0 })
        XCTAssertTrue(signature.valueParameterHasDefaultValues.allSatisfy { !$0 })
    }

    // MARK: - Runtime ABI registration

    /// The runtime helper `kk_input_stream_readAllBytes` must be declared in
    /// the FileIO ABI spec with the (streamRaw, outThrown) signature so the
    /// codegen pass can emit the correct extern declaration.
    func testRuntimeABISpecRegistersReadAllBytes() throws {
        let spec = RuntimeABISpec.fileIOFunctions.first { $0.name == "kk_input_stream_readAllBytes" }
        let unwrapped = try XCTUnwrap(
            spec,
            "kk_input_stream_readAllBytes must be registered in RuntimeABISpec+FileIO.swift"
        )
        XCTAssertEqual(unwrapped.parameters.count, 2)
        XCTAssertEqual(unwrapped.parameters[0].name, "streamRaw")
        XCTAssertEqual(unwrapped.parameters[0].type, .intptr)
        XCTAssertEqual(unwrapped.parameters[1].name, "outThrown")
        XCTAssertEqual(unwrapped.parameters[1].type, .nullableIntptrPointer)
        XCTAssertEqual(unwrapped.returnType, .intptr)
        XCTAssertEqual(unwrapped.section, "FileIO")
    }
}
