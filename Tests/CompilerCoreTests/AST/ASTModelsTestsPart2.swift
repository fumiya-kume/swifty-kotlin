@testable import CompilerCore
import XCTest

final class ASTModelsTestsPart2: XCTestCase {
    func testConstructorDeclAndDelegationCallInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 10, end: 50)
        let typeRef = TypeRefID(rawValue: 0)

        let delegationThis = ConstructorDelegationCall(
            kind: .this,
            args: [CallArgument(label: nil, expr: ExprID(rawValue: 0))],
            range: range
        )
        XCTAssertEqual(delegationThis.kind, .this)
        XCTAssertEqual(delegationThis.args.count, 1)
        XCTAssertEqual(delegationThis.range, range)

        let delegationSuper = ConstructorDelegationCall(
            kind: .super_,
            args: [],
            range: range
        )
        XCTAssertEqual(delegationSuper.kind, .super_)
        XCTAssertTrue(delegationSuper.args.isEmpty)
        XCTAssertNotEqual(delegationThis, delegationSuper)

        let ctorDefault = ConstructorDecl(range: range)
        XCTAssertEqual(ctorDefault.range, range)
        XCTAssertEqual(ctorDefault.modifiers, [])
        XCTAssertTrue(ctorDefault.valueParams.isEmpty)
        XCTAssertNil(ctorDefault.delegationCall)
        XCTAssertEqual(ctorDefault.body, .unit)

        let param = ValueParamDecl(name: interner.intern("x"), type: typeRef)
        let ctorFull = ConstructorDecl(
            range: range,
            modifiers: [.public],
            valueParams: [param],
            delegationCall: delegationThis,
            body: .block([ExprID(rawValue: 1)], range)
        )
        XCTAssertEqual(ctorFull.modifiers, [.public])
        XCTAssertEqual(ctorFull.valueParams.count, 1)
        XCTAssertNotNil(ctorFull.delegationCall)
        if case let .block(exprs, _) = ctorFull.body {
            XCTAssertEqual(exprs.count, 1)
        } else {
            XCTFail("Expected .block body")
        }

        let classDeclWithCtor = ClassDecl(
            range: range,
            name: interner.intern("Foo"),
            modifiers: [],
            typeParams: [],
            primaryConstructorParams: [],
            secondaryConstructors: [ctorFull]
        )
        XCTAssertEqual(classDeclWithCtor.secondaryConstructors.count, 1)
        XCTAssertTrue(classDeclWithCtor.initBlocks.isEmpty)
    }
}
