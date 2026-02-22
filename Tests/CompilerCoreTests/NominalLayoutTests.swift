import XCTest
@testable import CompilerCore

final class NominalLayoutTests: XCTestCase {

    // MARK: - Basic Init

    func testNominalLayoutMinimalInit() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout.objectHeaderWords, 2)
        XCTAssertEqual(layout.instanceFieldCount, 0)
        XCTAssertEqual(layout.instanceSizeWords, 2)
        XCTAssertTrue(layout.fieldOffsets.isEmpty)
        XCTAssertTrue(layout.vtableSlots.isEmpty)
        XCTAssertTrue(layout.itableSlots.isEmpty)
        XCTAssertEqual(layout.vtableSize, 0)
        XCTAssertEqual(layout.itableSize, 0)
        XCTAssertNil(layout.superClass)
    }

    // MARK: - Field Count Inference

    func testFieldCountInferredFromFieldOffsets() {
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 2, sym2: 3],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout.instanceFieldCount, 2)
    }

    func testFieldCountUsesMaxOfDeclaredAndInferred() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 5,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 2],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout.instanceFieldCount, 5)
    }

    // MARK: - Instance Size Inference

    func testInstanceSizeInferredFromFieldOffsets() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 4],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // inferredInstanceSizeWords = max(0, max(fieldOffsets.values) + 1) = 5
        // final = max(max(0, 5), 2 + 1) = 5
        XCTAssertEqual(layout.instanceSizeWords, 5)
    }

    func testInstanceSizeUsesHeaderPlusFieldCount() {
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let sym3 = SymbolID(rawValue: 2)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 2, sym2: 3, sym3: 4],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // inferredFieldCount = 3
        // inferredInstanceSizeWords = max(0, 4 + 1) = 5
        // final = max(max(0, 5), 2 + 3) = 5
        XCTAssertEqual(layout.instanceSizeWords, 5)
    }

    func testInstanceSizeUsesMaxOfAllSources() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 10,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout.instanceSizeWords, 10)
    }

    func testInstanceSizeWithEmptyFieldOffsetsUsesHeaderMinusOne() {
        let layout = NominalLayout(
            objectHeaderWords: 4,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [:],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // inferredInstanceSizeWords = max(0, (nil ?? (4-1)) + 1) = 4
        // final = max(max(0, 4), 4 + 0) = 4
        XCTAssertEqual(layout.instanceSizeWords, 4)
    }

    // MARK: - Vtable / Itable Size Inference

    func testVtableSizeInferredFromSlots() {
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [sym1: 0, sym2: 3],
            itableSlots: [:],
            superClass: nil
        )
        // inferredVtableSize = max(vtableSlots.values) + 1 = 3 + 1 = 4
        XCTAssertEqual(layout.vtableSize, 4)
    }

    func testItableSizeInferredFromSlots() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [sym1: 5],
            superClass: nil
        )
        // inferredItableSize = 5 + 1 = 6
        XCTAssertEqual(layout.itableSize, 6)
    }

    func testVtableSizeUsesMaxOfDeclaredAndInferred() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [sym1: 1],
            itableSlots: [:],
            vtableSize: 10,
            superClass: nil
        )
        // inferredVtableSize = 1 + 1 = 2; declared = 10; max(10, 2) = 10
        XCTAssertEqual(layout.vtableSize, 10)
    }

    func testItableSizeUsesMaxOfDeclaredAndInferred() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [sym1: 1],
            itableSize: 8,
            superClass: nil
        )
        // inferredItableSize = 1 + 1 = 2; declared = 8; max(8, 2) = 8
        XCTAssertEqual(layout.itableSize, 8)
    }

    func testEmptyVtableSlotsGivesZeroVtableSize() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout.vtableSize, 0)
        XCTAssertEqual(layout.itableSize, 0)
    }

    // MARK: - Superclass

    func testLayoutWithSuperclass() {
        let superSym = SymbolID(rawValue: 99)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: superSym
        )
        XCTAssertEqual(layout.superClass, superSym)
    }

    // MARK: - Equatable

    func testNominalLayoutEquality() {
        let layout1 = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        let layout2 = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout1, layout2)
    }

    func testNominalLayoutInequality() {
        let layout1 = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        let layout2 = NominalLayout(
            objectHeaderWords: 4,
            instanceFieldCount: 0,
            instanceSizeWords: 4,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertNotEqual(layout1, layout2)
    }

    // MARK: - NominalLayoutHint

    func testNominalLayoutHintAllNils() {
        let hint = NominalLayoutHint(
            declaredFieldCount: nil,
            declaredInstanceSizeWords: nil,
            declaredVtableSize: nil,
            declaredItableSize: nil
        )
        XCTAssertNil(hint.declaredFieldCount)
        XCTAssertNil(hint.declaredInstanceSizeWords)
        XCTAssertNil(hint.declaredVtableSize)
        XCTAssertNil(hint.declaredItableSize)
    }

    func testNominalLayoutHintWithValues() {
        let hint = NominalLayoutHint(
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 5,
            declaredVtableSize: 2,
            declaredItableSize: 1
        )
        XCTAssertEqual(hint.declaredFieldCount, 3)
        XCTAssertEqual(hint.declaredInstanceSizeWords, 5)
        XCTAssertEqual(hint.declaredVtableSize, 2)
        XCTAssertEqual(hint.declaredItableSize, 1)
    }

    func testNominalLayoutHintEquality() {
        let a = NominalLayoutHint(declaredFieldCount: 1, declaredInstanceSizeWords: 2, declaredVtableSize: 3, declaredItableSize: 4)
        let b = NominalLayoutHint(declaredFieldCount: 1, declaredInstanceSizeWords: 2, declaredVtableSize: 3, declaredItableSize: 4)
        XCTAssertEqual(a, b)
    }
}
