import XCTest
@testable import CompilerCore

final class ConstraintSolverTests: XCTestCase {
    func testSolveInitializesSubstitutionForAllVariables() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let vars = [TypeVarID(rawValue: 1), TypeVarID(rawValue: 2)]
        let constraints: [Constraint] = []

        let solution = solver.solve(vars: vars, constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[vars[0]], types.errorType)
        XCTAssertEqual(solution.substitution[vars[1]], types.errorType)
    }

    func testSolveSupportsSubtypeEqualAndSupertypeConstraints() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAny = types.nullableAnyType

        let constraints = [
            Constraint(kind: .subtype, left: intType, right: nullableAny),
            Constraint(kind: .equal, left: boolType, right: boolType),
            Constraint(kind: .supertype, left: nullableAny, right: intType)
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
        let solver = ConstraintSolver()
        let types = TypeSystem()
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
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 10)
        let t1 = TypeVarID(rawValue: 11)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    func testSolveVariableConstraintsFailsOnConflictingBounds() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 12)
        let blame = makeRange(start: 9, end: 12)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.code, "KSWIFTK-TYPE-0001")
        XCTAssertEqual(solution.failure?.primaryRange, blame)
        XCTAssertTrue(solution.failure?.message.contains("Conflicting bounds for type variable #12") ?? false)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolveVariableToVariableRelationPropagatesBounds() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 20)
        let t1 = TypeVarID(rawValue: 21)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveReportsUnsatisfiedConstraintWithRelationOperator() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 30)
        let blame = makeRange(start: 1, end: 3)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertNotNil(solution.failure)
    }

    func testSolveSupertypeConstraintSatisfied() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 40)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .type(anyType), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
    }

    func testSolveOnlyUpperBoundsUsesGLB() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 50)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNotNil(solution.substitution[t0])
    }

    func testSolveBothBoundsUsesLowerCandidate() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
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

    func testSolveErrorCandidateReportsFailure() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let t0 = TypeVarID(rawValue: 70)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertTrue(solution.failure?.message.contains("Failed to infer type variable") ?? false)
    }

    func testSolveMultipleVarRelationsConverge() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
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
        let solver = ConstraintSolver()
        let types = TypeSystem()
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
        let solver = ConstraintSolver()
        let types = TypeSystem()
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
}
