import XCTest
@testable import CompilerCore



extension ConstraintSolverTests {
    func testSolveTypeTypeFailurePlusVariableConflict(){
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 290)
        let blame = makeRange(start: 120, end: 125)

        // type-type constraint fails first: Bool <: Int (false)
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(boolType), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolvePostSubstitutionSupertypeViolation() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 295)
        let blame = makeRange(start: 130, end: 135)

        // equal normalizes to: t0 <: intType (upper) + intType <: t0 (lower)
        // supertype normalizes to: boolType <: t0 (lower)
        // lowers=[intType, boolType], uppers=[intType]
        // lub([intType, boolType]) = anyType, not subtype of intType → conflicting bounds
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Conflicting bounds"))
    }

    func testSolveAllVariablesGetErrorTypeOnEarlyFailure() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 300)
        let t1 = TypeVarID(rawValue: 301)
        let t2 = TypeVarID(rawValue: 302)

        // type-type constraint fails immediately; all vars should be errorType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(boolType), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t1), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t2), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
        XCTAssertEqual(solution.substitution[t1], types.errorType)
        XCTAssertEqual(solution.substitution[t2], types.errorType)
    }

    // MARK: - Complex variable dependencies

    func testSolveDiamondDependencyPattern() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 310)
        let t1 = TypeVarID(rawValue: 311)
        let t2 = TypeVarID(rawValue: 312)
        let t3 = TypeVarID(rawValue: 313)

        // Diamond: t0 → t1 → t3, t0 → t2 → t3
        // intType feeds in at t0, anyType caps at t3
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t3)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t3)),
            VariableConstraint(kind: .subtype, left: .variable(t3), right: .type(anyType))
        ]
        let solution = solver.solve(
            vars: [t0, t1, t2, t3],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        // t1, t2 propagated intType lower from t0
        XCTAssertEqual(solution.substitution[t1], intType)
        XCTAssertEqual(solution.substitution[t2], intType)
        XCTAssertEqual(solution.substitution[t3], intType)
    }

    func testSolveLongChainDependency() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 320)
        let t1 = TypeVarID(rawValue: 321)
        let t2 = TypeVarID(rawValue: 322)
        let t3 = TypeVarID(rawValue: 323)
        let t4 = TypeVarID(rawValue: 324)

        // Chain: intType → t0 → t1 → t2 → t3 → t4 → anyType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t3)),
            VariableConstraint(kind: .subtype, left: .variable(t3), right: .variable(t4)),
            VariableConstraint(kind: .subtype, left: .variable(t4), right: .type(anyType))
        ]
        let solution = solver.solve(
            vars: [t0, t1, t2, t3, t4],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        for v in [t0, t1, t2, t3, t4] {
            XCTAssertEqual(solution.substitution[v], intType)
        }
    }

    func testSolveMultipleIndependentVariableGroups() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let t0 = TypeVarID(rawValue: 330)
        let t1 = TypeVarID(rawValue: 331)
        let t2 = TypeVarID(rawValue: 332)
        let t3 = TypeVarID(rawValue: 333)

        // Group 1: t0 → t1 with intType
        // Group 2: t2 → t3 with stringType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .type(stringType), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t3))
        ]
        let solution = solver.solve(
            vars: [t0, t1, t2, t3],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
        XCTAssertEqual(solution.substitution[t2], stringType)
        XCTAssertEqual(solution.substitution[t3], stringType)
    }

    func testSolveVariableDependencyWithEqualAndSubtype() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 340)
        let t1 = TypeVarID(rawValue: 341)

        // t0 == intType, t0 <: t1, t1 <: anyType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    // MARK: - Coverage: relationOperator (private helper exposed as internal for testability)

    func testRelationOperatorReturnsCorrectSymbols() {
        let solver = ConstraintSolver()
        XCTAssertEqual(solver.relationOperator(for: .subtype), "<:")
        XCTAssertEqual(solver.relationOperator(for: .equal), "==")
        XCTAssertEqual(solver.relationOperator(for: .supertype), ":>")
    }

    // MARK: - Coverage: firstRelevantBlameRange returns nil

    func testSolveBlameRangeIsNilWhenVariableOnlyOnRightOfVarVarConstraint() throws {
        // When a variable only appears on the RIGHT side of a variable-to-variable
        // constraint, the firstRelevantBlameRange helper cannot find it because
        // the first switch case (.variable(let lhs), _) matches but lhs != target.
        // This exercises the `return nil` path in firstRelevantBlameRange.
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 400)
        let t1 = TypeVarID(rawValue: 401)

        // errorType propagates from t0 → t1 through var-var relation.
        // t1 is processed first (listed first in vars), so firstRelevantBlameRange
        // searches for t1 but only finds t0 on the left of the var-var constraint.
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(types.errorType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1))
        ]
        let solution = solver.solve(vars: [t1, t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer"))
        // blameRange should be nil since firstRelevantBlameRange couldn't find t1
        XCTAssertNil(failure.primaryRange)
    }

    func testSolveDiamondWithConflictingLeafBoundsFails() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 350)
        let t1 = TypeVarID(rawValue: 351)
        let t2 = TypeVarID(rawValue: 352)
        let blame = makeRange(start: 200, end: 205)

        // t0 → t1, t0 → t2; t1 upper-bounded by boolType, t2 lower-bounded by intType
        // t0 gets propagated lower intType from t2 and upper boolType from t1 → conflict
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(boolType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t2))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
    }
}
