@testable import CompilerCore
import XCTest

final class DurationSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testDurationOperatorMembersAreRegisteredWithReceiverType() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let expectedMembers: [(name: String, link: String, parameterTypes: [TypeID])] = [
            ("plus", "kk_duration_plus", [durationType]),
            ("minus", "kk_duration_minus", [durationType]),
            ("times", "kk_duration_times_int", [sema.types.intType]),
            ("div", "kk_duration_div_int", [sema.types.intType]),
            ("div", "kk_duration_div_duration", [durationType]),
            ("compareTo", "kk_duration_compareTo", [durationType]),
            ("unaryMinus", "kk_duration_unary_minus", []),
        ]

        for member in expectedMembers {
            let memberFQName = durationFQName + [interner.intern(member.name)]
            let matchingSymbols = sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == durationType
                    && signature.parameterTypes == member.parameterTypes
            }

            XCTAssertEqual(
                matchingSymbols.count,
                1,
                "Expected exactly one Duration.\(member.name) overload with receiverType=Duration"
            )
            let symbol = try XCTUnwrap(matchingSymbols.first)
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
            XCTAssertTrue(
                sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true,
                "Duration.\(member.name) should be an operatorFunction"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), member.link)
        }
    }
}
