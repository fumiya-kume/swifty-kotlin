@testable import CompilerCore
import Foundation
import XCTest

/// Tests for virtual dispatch (vtable/itable) lowering, codegen, and backend emission (P5-25).
final class VirtualDispatchTests: XCTestCase {
    // MARK: - Helpers

    /// Build a minimal symbol table + KIR module for an open class with a virtual method.
    /// Returns all symbols and the KIR module so tests can assert on lowered IR.
    func makeVtableFixture() -> (
        interner: StringInterner,
        arena: KIRArena,
        types: TypeSystem,
        symbols: SymbolTable,
        classSym: SymbolID,
        subclassSym: SymbolID,
        methodSym: SymbolID,
        receiverParamSym: SymbolID,
        callerSym: SymbolID,
        module: KIRModule
    ) {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyType = types.anyType

        // Define class "Animal"
        let classSym = symbols.define(
            kind: .class,
            name: interner.intern("Animal"),
            fqName: [interner.intern("Animal")],
            declSite: nil,
            visibility: .public
        )
        // Define subclass "Dog"
        let subclassSym = symbols.define(
            kind: .class,
            name: interner.intern("Dog"),
            fqName: [interner.intern("Dog")],
            declSite: nil,
            visibility: .public
        )
        // Register Dog as subtype of Animal
        symbols.setDirectSupertypes([classSym], for: subclassSym)

        // Define method "speak" on Animal
        let methodSym = symbols.define(
            kind: .function,
            name: interner.intern("speak"),
            fqName: [interner.intern("Animal"), interner.intern("speak")],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(classSym, for: methodSym)

        // Receiver parameter
        let receiverParamSym = symbols.define(
            kind: .local,
            name: interner.intern("this"),
            fqName: [interner.intern("Animal"), interner.intern("speak"), interner.intern("this")],
            declSite: nil,
            visibility: .internal
        )

        // Function signature for speak: (Animal) -> Unit
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: anyType,
                parameterTypes: [],
                returnType: types.unitType,
                valueParameterSymbols: []
            ),
            for: methodSym
        )

        // NominalLayout for Animal with vtable
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: 0,
                instanceSizeWords: 2,
                vtableSlots: [methodSym: 0],
                itableSlots: [:],
                superClass: nil
            ),
            for: classSym
        )

        // Build KIR: caller function that invokes speak on Animal receiver
        let callerSym = symbols.define(
            kind: .function,
            name: interner.intern("callSpeak"),
            fqName: [interner.intern("callSpeak")],
            declSite: nil,
            visibility: .public
        )
        let callerParamSym = symbols.define(
            kind: .local,
            name: interner.intern("animal"),
            fqName: [interner.intern("callSpeak"), interner.intern("animal")],
            declSite: nil,
            visibility: .internal
        )

        let receiverExpr = arena.appendExpr(.symbolRef(callerParamSym), type: anyType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        // Build a virtualCall instruction directly (as if BuildKIRPass emitted it)
        let methodFn = KIRFunction(
            symbol: methodSym,
            name: interner.intern("speak"),
            params: [KIRParameter(symbol: receiverParamSym, type: anyType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("callSpeak"),
            params: [KIRParameter(symbol: callerParamSym, type: anyType)],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: methodSym,
                    callee: interner.intern("speak"),
                    receiver: receiverExpr,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(methodFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        return (interner, arena, types, symbols, classSym, subclassSym, methodSym, receiverParamSym, callerSym, module)
    }

    /// Build a minimal symbol table + KIR module for an interface method call.
    func makeItableFixture() -> (
        interner: StringInterner,
        arena: KIRArena,
        types: TypeSystem,
        symbols: SymbolTable,
        interfaceSym: SymbolID,
        methodSym: SymbolID,
        callerSym: SymbolID,
        module: KIRModule
    ) {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyType = types.anyType

        // Define interface "Drawable"
        let interfaceSym = symbols.define(
            kind: .interface,
            name: interner.intern("Drawable"),
            fqName: [interner.intern("Drawable")],
            declSite: nil,
            visibility: .public
        )

        // Define method "draw" on Drawable
        let methodSym = symbols.define(
            kind: .function,
            name: interner.intern("draw"),
            fqName: [interner.intern("Drawable"), interner.intern("draw")],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(interfaceSym, for: methodSym)

        let receiverParamSym = symbols.define(
            kind: .local,
            name: interner.intern("this"),
            fqName: [interner.intern("Drawable"), interner.intern("draw"), interner.intern("this")],
            declSite: nil,
            visibility: .internal
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: anyType,
                parameterTypes: [],
                returnType: types.unitType,
                valueParameterSymbols: []
            ),
            for: methodSym
        )

        // NominalLayout for Drawable with itable
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: 0,
                instanceSizeWords: 2,
                vtableSlots: [methodSym: 0],
                itableSlots: [interfaceSym: 0],
                superClass: nil
            ),
            for: interfaceSym
        )

        // Build caller that invokes draw via itable
        let callerSym = symbols.define(
            kind: .function,
            name: interner.intern("callDraw"),
            fqName: [interner.intern("callDraw")],
            declSite: nil,
            visibility: .public
        )
        let callerParamSym = symbols.define(
            kind: .local,
            name: interner.intern("d"),
            fqName: [interner.intern("callDraw"), interner.intern("d")],
            declSite: nil,
            visibility: .internal
        )

        let receiverExpr = arena.appendExpr(.symbolRef(callerParamSym), type: anyType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("callDraw"),
            params: [KIRParameter(symbol: callerParamSym, type: anyType)],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: methodSym,
                    callee: interner.intern("draw"),
                    receiver: receiverExpr,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .itable(interfaceSlot: 0, methodSlot: 0)
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let methodFn = KIRFunction(
            symbol: methodSym,
            name: interner.intern("draw"),
            params: [KIRParameter(symbol: receiverParamSym, type: anyType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(methodFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        return (interner, arena, types, symbols, interfaceSym, methodSym, callerSym, module)
    }

    // MARK: - 1. KIRDispatchKind enum tests

    func testKIRDispatchKindVtableEquality() {
        let a = KIRDispatchKind.vtable(slot: 3)
        let b = KIRDispatchKind.vtable(slot: 3)
        let c = KIRDispatchKind.vtable(slot: 5)
        XCTAssertEqual(a, b, "vtable with same slot should be equal")
        XCTAssertNotEqual(a, c, "vtable with different slot should not be equal")
    }

    func testKIRDispatchKindItableEquality() {
        let a = KIRDispatchKind.itable(interfaceSlot: 1, methodSlot: 2)
        let b = KIRDispatchKind.itable(interfaceSlot: 1, methodSlot: 2)
        let c = KIRDispatchKind.itable(interfaceSlot: 1, methodSlot: 3)
        let d = KIRDispatchKind.itable(interfaceSlot: 0, methodSlot: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c, "different methodSlot should not be equal")
        XCTAssertNotEqual(a, d, "different interfaceSlot should not be equal")
    }

    func testKIRDispatchKindVtableNotEqualToItable() {
        let vtable = KIRDispatchKind.vtable(slot: 0)
        let itable = KIRDispatchKind.itable(interfaceSlot: 0, methodSlot: 0)
        XCTAssertNotEqual(vtable, itable, "vtable and itable should never be equal")
    }

    // MARK: - 2. virtualCall instruction construction

    func testVirtualCallInstructionStoresReceiverSeparately() {
        let arena = KIRArena()
        let types = TypeSystem()
        let receiverExpr = arena.appendExpr(.temporary(0), type: types.anyType)
        let argExpr = arena.appendExpr(.temporary(1), type: types.anyType)
        let resultExpr = arena.appendExpr(.temporary(2), type: types.unitType)

        let instruction = KIRInstruction.virtualCall(
            symbol: SymbolID(rawValue: 10),
            callee: InternedString(rawValue: 1),
            receiver: receiverExpr,
            arguments: [argExpr],
            result: resultExpr,
            canThrow: false,
            thrownResult: nil,
            dispatch: .vtable(slot: 0)
        )

        // Verify receiver is NOT in arguments
        guard case let .virtualCall(_, _, receiver, arguments, _, _, _, _) = instruction else {
            XCTFail("Expected virtualCall instruction")
            return
        }
        XCTAssertEqual(receiver, receiverExpr, "Receiver should be stored separately")
        XCTAssertEqual(arguments.count, 1, "Arguments should contain only the actual argument, not receiver")
        XCTAssertEqual(arguments[0], argExpr, "First argument should be the method arg, not receiver")
        XCTAssertNotEqual(arguments[0], receiverExpr, "Receiver should not be in arguments array")
    }

    // MARK: - 3. ABILoweringPass boxing for virtualCall

    func testABILoweringBoxesIntArgumentForVirtualCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 4000)
        let targetSym = SymbolID(rawValue: 4001)
        let targetParamSym = SymbolID(rawValue: 4002)

        let targetName = interner.intern("virtualAcceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [anyNullableType],
                returnType: types.unitType,
                valueParameterSymbols: [targetParamSym]
            ),
            for: targetSym
        )

        let receiverExpr = arena.appendExpr(.temporary(0), type: types.anyType)
        let argExpr = arena.appendExpr(.intLiteral(42), type: intType)
        let resultExpr = arena.appendExpr(.temporary(2), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: targetSym,
                    callee: targetName,
                    receiver: receiverExpr,
                    arguments: [argExpr],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ABIBoxVirtual",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        // Check that boxing call was inserted before the virtualCall
        let callees = lowered.body.compactMap { instruction -> String? in
            switch instruction {
            case let .call(_, callee, _, _, _, _, _):
                return interner.resolve(callee)
            case let .virtualCall(_, callee, _, _, _, _, _, _):
                return "vc:" + interner.resolve(callee)
            default:
                return nil
            }
        }
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int call for Int -> Any? boxing in virtualCall arg, got: \(callees)")
        XCTAssertTrue(callees.contains("vc:virtualAcceptAny"), "Expected virtualCall to remain after lowering, got: \(callees)")
    }

    // MARK: - 11. InlineLoweringPass: virtualCall alias resolution

    // MARK: - 12. Regression: existing .call instructions still work

    // MARK: - 13. Coroutine lowering: extractCallInfo for virtualCall

    // MARK: - 14. Virtual suspend call emits virtualCall (not .call) in state machine

    // MARK: - 15. resolveVirtualDispatch: open class with subtypes -> vtable

    // MARK: - 16. resolveVirtualDispatch: final class -> static dispatch (no virtualCall)

    // MARK: - 17. virtualCall with multiple arguments: receiver separate, args correct count
}
