@testable import CompilerCore
import Foundation
import XCTest

final class SemanticsAndUtilitiesRegressionTests: XCTestCase {
    func testTypeSystemLUBAndGLB() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))
        let boolNN = types.make(.primitive(.boolean, .nonNull))

        XCTAssertEqual(types.lub([]), types.errorType)
        XCTAssertEqual(types.lub([intNN, intNN]), intNN)
        XCTAssertEqual(types.lub([intNN, intNullable]), types.nullableAnyType)

        XCTAssertEqual(types.glb([]), types.errorType)
        XCTAssertEqual(types.glb([intNN, intNN]), intNN)
        XCTAssertEqual(types.glb([intNN, types.nothingType]), types.nothingType)

        let glbMixed = types.glb([intNN, boolNN])
        XCTAssertEqual(types.kind(of: glbMixed), .intersection([intNN, boolNN]))

        XCTAssertEqual(types.kind(of: TypeID(rawValue: 9999)), .error)
    }

    func testTypeSystemAnyNonNullSubtypeCoversClassFunctionIntersectionAndDefaultCases() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))

        let classNN = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nonNull
        )))
        let classNullable = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nullable
        )))

        let fnNN = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnNullable = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nullable
        )))

        let intersectionAllNonNull = types.make(.intersection([intNN, classNN]))
        let intersectionWithNullable = types.make(.intersection([intNN, intNullable]))

        XCTAssertTrue(types.isSubtype(classNN, types.anyType))
        XCTAssertFalse(types.isSubtype(classNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(fnNN, types.anyType))
        XCTAssertFalse(types.isSubtype(fnNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(intersectionAllNonNull, types.anyType))
        // With corrected intersection subtype rules (P5-97): A & B <: C if ANY part <: C.
        // intersection([Int, Int?]) <: Any is true because Int <: Any.
        XCTAssertTrue(types.isSubtype(intersectionWithNullable, types.anyType))
        XCTAssertFalse(types.isSubtype(types.nullableAnyType, types.anyType))

        let fnWithReceiver = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnWithoutReceiver = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(fnWithReceiver, fnWithoutReceiver))
    }

    func testSemanticsBindingTableAndSymbolTableScopes() {
        let interner = StringInterner()
        let symbols = SymbolTable()

        let pkg = symbols.define(
            kind: .package,
            name: interner.intern("pkg"),
            fqName: [interner.intern("pkg")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let fn = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: [interner.intern("pkg"), interner.intern("run")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .suspendFunction]
        )

        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols.symbol(pkg)?.kind, .package)
        XCTAssertEqual(symbols.lookup(fqName: [interner.intern("pkg")]), pkg)

        let signature = FunctionSignature(parameterTypes: [TypeSystem().anyType], returnType: TypeSystem().unitType)
        symbols.setFunctionSignature(signature, for: fn)
        XCTAssertEqual(symbols.functionSignature(for: fn)?.parameterTypes.count, 1)

        let root = PackageScope(parent: nil, symbols: symbols)
        let fileScope = FileScope(parent: root, symbols: symbols)
        fileScope.insert(fn)
        XCTAssertEqual(fileScope.lookup(interner.intern("run")), [fn])
        XCTAssertTrue(root.lookup(interner.intern("run")).isEmpty)

        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let decl = DeclID(rawValue: 2)
        bindings.bindExprType(expr, type: TypeSystem().anyType)
        bindings.bindIdentifier(expr, symbol: fn)
        bindings.bindCall(expr, binding: CallBinding(chosenCallee: fn, substitutedTypeArguments: [], parameterMapping: [0: 0]))
        bindings.bindCallableTarget(expr, target: .symbol(fn))
        bindings.bindCallableValueCall(
            expr,
            binding: CallableValueCallBinding(
                target: .localValue(fn),
                functionType: TypeSystem().anyType,
                parameterMapping: [0: 0]
            )
        )
        bindings.bindCallableTarget(expr, target: .localValue(fn))
        bindings.bindCaptureSymbols(expr, symbols: [fn, fn])
        bindings.bindDecl(decl, symbol: fn)
        bindings.bindCatchClause(expr, binding: CatchClauseBinding(parameterSymbol: fn, parameterType: TypeSystem().anyType))

        XCTAssertEqual(bindings.identifierSymbol(for: expr), fn)
        XCTAssertEqual(bindings.callBinding(for: expr)?.chosenCallee, fn)
        XCTAssertEqual(bindings.callableTarget(for: expr), .localValue(fn))
        XCTAssertEqual(bindings.callableValueCallBinding(for: expr)?.parameterMapping, [0: 0])
        XCTAssertEqual(bindings.catchClauseBinding(for: expr)?.parameterSymbol, fn)
        XCTAssertEqual(bindings.captureSymbols(for: expr), [fn])
        XCTAssertEqual(bindings.declSymbol(for: decl), fn)
        XCTAssertFalse(bindings.isSuperCallExpr(expr))
    }

    func testImportAliasDeclStoresAliasField() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 10)

        let noAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: nil)
        XCTAssertNil(noAlias.alias)

        let withAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: interner.intern("X"))
        XCTAssertEqual(withAlias.alias, interner.intern("X"))
    }

    func testConditionBranchStructCreation() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 100)
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let trueState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        let falseState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [stringType], nullability: .nonNull, isStable: true)
        ])
        let branch = ConditionBranch(trueState: trueState, falseState: falseState)

        XCTAssertEqual(branch.trueState.variables[sym]?.possibleTypes, [intType])
        XCTAssertEqual(branch.falseState.variables[sym]?.possibleTypes, [stringType])

        let merged = analyzer.merge(branch.trueState, branch.falseState)
        XCTAssertEqual(merged.variables[sym]?.possibleTypes.count, 2)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(intType) == true)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(stringType) == true)
    }
}

final class CommandRunnerErrorPathTests: XCTestCase {
    func testRunReturnsStdoutOnSuccess() throws {
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-c", "printf 'ok'"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ok")
    }

    func testRunThrowsNonZeroExitWithCapturedStderr() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["sh", "-c", "printf 'err' >&2; exit 7"]
            )
        ) { error in
            guard case let CommandRunnerError.nonZeroExit(result) = error else {
                XCTFail("Expected nonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(result.exitCode, 7)
            XCTAssertEqual(result.stderr, "err")
        }
    }

    func testRunThrowsLaunchFailedForMissingExecutable() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/definitely/missing/executable",
                arguments: []
            )
        ) { error in
            guard case let CommandRunnerError.launchFailed(message) = error else {
                XCTFail("Expected launchFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Failed to launch"))
        }
    }
}
