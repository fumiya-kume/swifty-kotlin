@testable import CompilerCore
import XCTest

extension ConstraintSolverTests {
    func testSolutionInitStoresAllFields() {
        let sub: [TypeVarID: TypeID] = [TypeVarID(rawValue: 0): TypeID(rawValue: 5)]
        let diag = Diagnostic(
            severity: .error,
            code: "TEST",
            message: "test",
            primaryRange: nil,
            secondaryRanges: []
        )
        let solution = Solution(substitution: sub, isSuccess: false, failure: diag)
        XCTAssertEqual(solution.substitution[TypeVarID(rawValue: 0)], TypeID(rawValue: 5))
        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.code, "TEST")
    }

    func testSolveVarToVarConvergesWithoutChange() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 92)
        let t1 = TypeVarID(rawValue: 93)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t1))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    func testConstraintInitWithBlameRange() {
        let blame = makeRange(start: 10, end: 20)
        let constraint = Constraint(
            kind: .equal,
            left: TypeID(rawValue: 1),
            right: TypeID(rawValue: 2),
            blameRange: blame
        )
        XCTAssertEqual(constraint.kind, .equal)
        XCTAssertEqual(constraint.blameRange, blame)
    }

    func testConstraintInitWithoutBlameRange() {
        let constraint = Constraint(
            kind: .subtype,
            left: TypeID(rawValue: 1),
            right: TypeID(rawValue: 2)
        )
        XCTAssertNil(constraint.blameRange)
    }

    func testVariableConstraintInitWithBlameRange() {
        let blame = makeRange(start: 0, end: 5)
        let vc = VariableConstraint(
            kind: .supertype,
            left: .variable(TypeVarID(rawValue: 1)),
            right: .type(TypeID(rawValue: 2)),
            blameRange: blame
        )
        XCTAssertEqual(vc.kind, .supertype)
        XCTAssertEqual(vc.blameRange, blame)
    }

    func testVariableConstraintInitWithoutBlameRange() {
        let vc = VariableConstraint(
            kind: .equal,
            left: .type(TypeID(rawValue: 1)),
            right: .variable(TypeVarID(rawValue: 2))
        )
        XCTAssertNil(vc.blameRange)
    }

    func testSolveBothBoundsUsesLowerCandidate() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 60)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveErrorCandidateReportsFailure() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 70)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer type variable"))
    }

    func testSolveMultipleVarRelationsConverge() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 80)
        let t1 = TypeVarID(rawValue: 81)
        let t2 = TypeVarID(rawValue: 82)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
    }

    func testTypeVarIDInvalidAndEquality() {
        XCTAssertEqual(TypeVarID.invalid.rawValue, -1)
        XCTAssertEqual(TypeVarID(), TypeVarID.invalid)
        XCTAssertNotEqual(TypeVarID(rawValue: 0), TypeVarID(rawValue: 1))
    }

    func testConstraintOperandEquality() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let op1 = ConstraintOperand.type(intType)
        let op2 = ConstraintOperand.type(intType)
        let op3 = ConstraintOperand.variable(TypeVarID(rawValue: 1))
        let op4 = ConstraintOperand.variable(TypeVarID(rawValue: 1))

        XCTAssertEqual(op1, op2)
        XCTAssertEqual(op3, op4)
        XCTAssertNotEqual(op1, op3)
    }

    func testSolveSupertypeConstraintViolationReportsFailure() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 90)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .type(intType), right: .type(boolType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
    }

    func testFirstRelevantBlameRangeFindsRightSideVariable() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 100)
        let blame = makeRange(start: 20, end: 25)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.primaryRange, blame)
    }

    func testSolveUnresolvedVariableInConstraintProducesFailure() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 60)
        let tUnknown = TypeVarID(rawValue: 99)
        let blame = makeRange(start: 1, end: 2)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(tUnknown), right: .type(intType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("unresolved variables"))
    }

    func testSolveConflictingBoundsWithMixedTypeTypeConstraints() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 95)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .type(anyType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
    }

    func testSolveCandidateErrorTypeFromUpperBoundsOnly() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 101)
        let blame = makeRange(start: 0, end: 1)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer"))
    }

    func testTypeVarIDInvalidIsMinusOne() {
        XCTAssertEqual(TypeVarID.invalid.rawValue, -1)
        XCTAssertEqual(TypeVarID().rawValue, -1)
    }

    func testSolveRenderBoundsIncludesEmptyMarker() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 110)
        let blame = makeRange(start: 60, end: 65)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("lower=[-]"))
    }
}
