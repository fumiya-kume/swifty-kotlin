@testable import CompilerCore
import XCTest

final class ConstraintSolverTests: XCTestCase {
    func makeDeps() -> (solver: ConstraintSolver, types: TypeSystem) {
        (ConstraintSolver(), TypeSystem())
    }

    func testSolveInitializesSubstitutionForAllVariables() {
        let (solver, types) = makeDeps()
        let vars = [TypeVarID(rawValue: 1), TypeVarID(rawValue: 2)]
        let constraints: [Constraint] = []

        let solution = solver.solve(vars: vars, constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[vars[0]], types.errorType)
        XCTAssertEqual(solution.substitution[vars[1]], types.errorType)
    }

    func testSolveSupportsSubtypeEqualAndSupertypeConstraints() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAny = types.nullableAnyType

        let constraints = [
            Constraint(kind: .subtype, left: intType, right: nullableAny),
            Constraint(kind: .equal, left: boolType, right: boolType),
            Constraint(kind: .supertype, left: nullableAny, right: intType),
        ]

        let solution = solver.solve(
            vars: [TypeVarID(rawValue: 3)],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
    }

    func testSolveReturnsFailureDiagnosticForUnsatisfiedConstraint() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let variable = TypeVarID(rawValue: 4)
        let blameRange = makeRange(start: 2, end: 5)

        let solution = solver.solve(
            vars: [variable],
            constraints: [Constraint(kind: .subtype, left: boolType, right: intType, blameRange: blameRange)],
            typeSystem: types
        )

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[variable], types.errorType)
        XCTAssertEqual(solution.failure?.severity, .error)
        XCTAssertEqual(solution.failure?.code, "KSWIFTK-TYPE-0001")
        XCTAssertEqual(solution.failure?.primaryRange, blameRange)
    }

    func testSolveVariableConstraintsBindsTypeVariablesFromEqualityAndBounds() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 10)
        let t1 = TypeVarID(rawValue: 11)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    func testSolveVariableToVariableRelationPropagatesBounds() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 20)
        let t1 = TypeVarID(rawValue: 21)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolvePostSubstitutionConstraintVerificationFailure() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 30)
        let blame = makeRange(start: 0, end: 3)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
        // With corrected intersection subtype rules (P5-97), the solver now detects
        // the conflict at the bound-checking phase rather than post-substitution.
        XCTAssertTrue(failure.message.contains("not satisfied") || failure.message.contains("not a subtype"))
    }

    func testSolveSupertypeConstraintKindSatisfaction() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 40)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .type(anyType), right: .variable(t0)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveOnlyUpperBoundsUsesGLB() {
        let (solver, types) = makeDeps()
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 50)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNotNil(solution.substitution[t0])
    }

    func testSolveVariableConstraintsFailsOnConflictingBounds() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 12)
        let blame = makeRange(start: 9, end: 12)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
        XCTAssertEqual(failure.primaryRange, blame)
        XCTAssertTrue(failure.message.contains("Conflicting bounds for type variable #12"))
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolveSupertypeConstraintAddsLowerBound() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 31)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveFailsWhenCandidateIsErrorType() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 41)
        let blame = makeRange(start: 40, end: 45)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(types.errorType), right: .variable(t0), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer"))
    }

    func testSolveResolvesVariableWithOnlyUpperBound() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 51)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(intType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveResolvesVariableWithCompatibleLowerAndUpperBounds() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 61)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testConstraintOperandEquatable() {
        let a: ConstraintOperand = .type(TypeID(rawValue: 1))
        let b: ConstraintOperand = .type(TypeID(rawValue: 1))
        let c: ConstraintOperand = .variable(TypeVarID(rawValue: 2))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSolveDuplicateBoundsAreDeduped() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 70)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveBlameRangeFromRightSideVariable() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 80)
        let blame = makeRange(start: 50, end: 55)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .type(boolType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.primaryRange, blame)
    }
}
