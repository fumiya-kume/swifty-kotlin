@testable import CompilerCore
import Foundation
import XCTest

final class StreamsSyntheticMemberLinkTests: XCTestCase {
    func testJvmStreamsAsSequenceSurfacesResolveInSource() throws {
        let source = """
        import java.util.stream.DoubleStream
        import java.util.stream.IntStream
        import java.util.stream.LongStream
        import java.util.stream.Stream
        import kotlin.streams.asSequence

        fun streamSize(values: Stream<String>): Int = values.asSequence().toList().size
        fun intStreamSize(values: IntStream): Int = values.asSequence().toList().size
        fun longStreamSize(values: LongStream): Int = values.asSequence().toList().size
        fun doubleStreamSize(values: DoubleStream): Int = values.asSequence().toList().size
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected kotlin.streams.asSequence surfaces to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let links = Set(
                sema.symbols.allSymbols()
                    .filter { $0.fqName.prefix(2).map { ctx.interner.resolve($0) } == ["kotlin", "streams"] }
                    .compactMap { sema.symbols.externalLinkName(for: $0.id) }
            )
            XCTAssertTrue(links.contains("kk_stream_asSequence"))
            XCTAssertTrue(links.contains("kk_int_stream_asSequence"))
            XCTAssertTrue(links.contains("kk_long_stream_asSequence"))
            XCTAssertTrue(links.contains("kk_double_stream_asSequence"))
        }
    }

    func testJvmSequenceAsStreamSurfaceResolvesInSource() throws {
        let source = """
        import java.util.stream.Stream
        import kotlin.sequences.Sequence
        import kotlin.streams.asStream

        fun toStream(values: Sequence<String>): Stream<String> = values.asStream()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected kotlin.streams.asStream surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let links = Set(
                sema.symbols.allSymbols()
                    .filter { $0.fqName.prefix(2).map { ctx.interner.resolve($0) } == ["kotlin", "streams"] }
                    .compactMap { sema.symbols.externalLinkName(for: $0.id) }
            )
            XCTAssertTrue(links.contains("kk_sequence_asStream"))
        }
    }

    func testJvmStreamsAsSequenceReturnShapes() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let asSequenceSymbols = sema.symbols.allSymbols().filter { symbol in
                symbol.fqName.count >= 3
                    && symbol.fqName.prefix(2).map { ctx.interner.resolve($0) } == ["kotlin", "streams"]
                    && ctx.interner.resolve(symbol.name) == "asSequence"
            }
            XCTAssertEqual(asSequenceSymbols.count, 4)
            for symbol in asSequenceSymbols {
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol.id))
                guard case let .classType(sequenceType) = sema.types.kind(of: signature.returnType) else {
                    return XCTFail("Expected asSequence to return Sequence, got \(sema.types.kind(of: signature.returnType))")
                }
                XCTAssertEqual(
                    try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(sequenceType.classSymbol)?.name)),
                    "Sequence"
                )
            }
        }
    }

    func testJvmSequenceAsStreamReturnShape() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let asStreamSymbols = sema.symbols.allSymbols().filter { symbol in
                symbol.fqName.count >= 3
                    && symbol.fqName.prefix(2).map { ctx.interner.resolve($0) } == ["kotlin", "streams"]
                    && ctx.interner.resolve(symbol.name) == "asStream"
            }
            XCTAssertEqual(asStreamSymbols.count, 1)

            let symbol = try XCTUnwrap(asStreamSymbols.first)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol.id), "kk_sequence_asStream")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol.id))
            guard case let .classType(sequenceType) = sema.types.kind(of: try XCTUnwrap(signature.receiverType)) else {
                return XCTFail("Expected asStream receiver to be Sequence, got \(String(describing: signature.receiverType))")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(sequenceType.classSymbol)?.name)),
                "Sequence"
            )

            guard case let .classType(streamType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected asStream to return Stream, got \(sema.types.kind(of: signature.returnType))")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(streamType.classSymbol)?.name)),
                "Stream"
            )
        }
    }
}
