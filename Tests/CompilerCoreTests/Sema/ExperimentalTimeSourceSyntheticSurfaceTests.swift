@testable import CompilerCore
import XCTest

final class ExperimentalTimeSourceSyntheticSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected experimental time source surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testAbstractDoubleTimeSourceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let timeSourceSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [interner.intern("TimeSource")]))
        XCTAssertEqual(sema.symbols.symbol(timeSourceSymbol)?.kind, .interface)

        let withComparableMarksSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("WithComparableMarks"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(withComparableMarksSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.parentSymbol(for: withComparableMarksSymbol), timeSourceSymbol)
        XCTAssertEqual(sema.symbols.directSupertypes(for: withComparableMarksSymbol), [timeSourceSymbol])

        let abstractDoubleSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractDoubleTimeSource"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(abstractDoubleSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(abstractDoubleSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(sema.symbols.directSupertypes(for: abstractDoubleSymbol), [withComparableMarksSymbol])

        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("DurationUnit"),
        ]))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let abstractDoubleType = sema.types.make(.classType(ClassType(
            classSymbol: abstractDoubleSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorSymbol = try XCTUnwrap(sema.symbols.lookupAll(
            fqName: kotlinTime + [interner.intern("AbstractDoubleTimeSource"), interner.intern("<init>")]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        XCTAssertEqual(constructorSignature.receiverType, abstractDoubleType)
        XCTAssertEqual(constructorSignature.parameterTypes, [durationUnitType])
        XCTAssertEqual(constructorSignature.returnType, abstractDoubleType)

        let unitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractDoubleTimeSource"),
            interner.intern("unit"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(unitSymbol)?.visibility, .protected)
        XCTAssertEqual(sema.symbols.propertyType(for: unitSymbol), durationUnitType)

        let readSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("AbstractDoubleTimeSource"),
            interner.intern("read"),
        ]).first)
        let readSignature = try XCTUnwrap(sema.symbols.functionSignature(for: readSymbol))
        XCTAssertEqual(sema.symbols.symbol(readSymbol)?.visibility, .protected)
        XCTAssertTrue(sema.symbols.symbol(readSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(readSignature.receiverType, abstractDoubleType)
        XCTAssertEqual(readSignature.parameterTypes, [])
        XCTAssertEqual(readSignature.returnType, sema.types.doubleType)
    }

    func testAbstractDoubleTimeSourceCanBeSubclassedInSource() throws {
        let source = """
        import kotlin.time.AbstractDoubleTimeSource
        import kotlin.time.DurationUnit
        import kotlin.time.ExperimentalTime

        @OptIn(ExperimentalTime::class)
        class ProbeSource : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
            protected override fun read(): Double = 12.5
        }

        @OptIn(ExperimentalTime::class)
        fun mark(source: ProbeSource) = source.markNow()
        """

        let (sema, interner) = try makeSema(source: source)
        let markSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("mark")]))
        let markSignature = try XCTUnwrap(sema.symbols.functionSignature(for: markSymbol))
        let comparableTimeMarkSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("ComparableTimeMark"),
        ]))
        let comparableTimeMarkType = sema.types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(markSignature.returnType, comparableTimeMarkType)
    }
<<<<<<< HEAD

    func testAbstractLongTimeSourceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let withComparableMarksSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("WithComparableMarks"),
        ]))
        let abstractLongSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(abstractLongSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(abstractLongSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(sema.symbols.directSupertypes(for: abstractLongSymbol), [withComparableMarksSymbol])

        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("DurationUnit"),
        ]))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let abstractLongType = sema.types.make(.classType(ClassType(
            classSymbol: abstractLongSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorSymbol = try XCTUnwrap(sema.symbols.lookupAll(
            fqName: kotlinTime + [interner.intern("AbstractLongTimeSource"), interner.intern("<init>")]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        XCTAssertEqual(constructorSignature.receiverType, abstractLongType)
        XCTAssertEqual(constructorSignature.parameterTypes, [durationUnitType])
        XCTAssertEqual(constructorSignature.returnType, abstractLongType)

        let unitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
            interner.intern("unit"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(unitSymbol)?.visibility, .protected)
        XCTAssertEqual(sema.symbols.propertyType(for: unitSymbol), durationUnitType)

        let readSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: kotlinTime + [
            interner.intern("AbstractLongTimeSource"),
            interner.intern("read"),
        ]).first)
        let readSignature = try XCTUnwrap(sema.symbols.functionSignature(for: readSymbol))
        XCTAssertEqual(sema.symbols.symbol(readSymbol)?.visibility, .protected)
        XCTAssertTrue(sema.symbols.symbol(readSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(readSignature.receiverType, abstractLongType)
        XCTAssertEqual(readSignature.parameterTypes, [])
        XCTAssertEqual(readSignature.returnType, sema.types.longType)
    }

    func testAbstractLongTimeSourceCanBeSubclassedInSource() throws {
        let source = """
        import kotlin.time.AbstractLongTimeSource
        import kotlin.time.DurationUnit
        import kotlin.time.ExperimentalTime

        @OptIn(ExperimentalTime::class)
        class ProbeLongSource : AbstractLongTimeSource(DurationUnit.NANOSECONDS) {
            protected override fun read(): Long = 42L
        }

        @OptIn(ExperimentalTime::class)
        fun mark(source: ProbeLongSource) = source.markNow()
        """

        let (sema, interner) = try makeSema(source: source)
        let markSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("mark")]))
        let markSignature = try XCTUnwrap(sema.symbols.functionSignature(for: markSymbol))
        let comparableTimeMarkSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("ComparableTimeMark"),
        ]))
        let comparableTimeMarkType = sema.types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(markSignature.returnType, comparableTimeMarkType)
    }
=======
>>>>>>> c7d1e8c0b (Add AbstractDoubleTimeSource surface)
}
