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
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }
}
