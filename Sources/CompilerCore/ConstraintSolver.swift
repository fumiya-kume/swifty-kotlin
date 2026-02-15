public struct TypeVarID: Hashable {
    public let rawValue: Int32

    public static let invalid = TypeVarID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum ConstraintKind {
    case subtype
    case equal
    case supertype
}

public struct Constraint {
    public let kind: ConstraintKind
    public let left: TypeID
    public let right: TypeID
    public let blameRange: SourceRange?

    public init(kind: ConstraintKind, left: TypeID, right: TypeID, blameRange: SourceRange? = nil) {
        self.kind = kind
        self.left = left
        self.right = right
        self.blameRange = blameRange
    }
}

public enum ConstraintOperand: Equatable {
    case type(TypeID)
    case variable(TypeVarID)
}

public struct VariableConstraint {
    public let kind: ConstraintKind
    public let left: ConstraintOperand
    public let right: ConstraintOperand
    public let blameRange: SourceRange?

    public init(
        kind: ConstraintKind,
        left: ConstraintOperand,
        right: ConstraintOperand,
        blameRange: SourceRange? = nil
    ) {
        self.kind = kind
        self.left = left
        self.right = right
        self.blameRange = blameRange
    }
}

public struct Solution {
    public let substitution: [TypeVarID: TypeID]
    public let isSuccess: Bool
    public let failure: Diagnostic?

    public init(substitution: [TypeVarID: TypeID], isSuccess: Bool, failure: Diagnostic?) {
        self.substitution = substitution
        self.isSuccess = isSuccess
        self.failure = failure
    }
}

public final class ConstraintSolver {
    public init() {}

    public func solve(
        vars: [TypeVarID],
        constraints: [Constraint],
        typeSystem: TypeSystem
    ) -> Solution {
        let converted = constraints.map { constraint in
            VariableConstraint(
                kind: constraint.kind,
                left: .type(constraint.left),
                right: .type(constraint.right),
                blameRange: constraint.blameRange
            )
        }
        return solve(vars: vars, constraints: converted, typeSystem: typeSystem)
    }

    public func solve(
        vars: [TypeVarID],
        constraints: [VariableConstraint],
        typeSystem: TypeSystem
    ) -> Solution {
        var lowerBounds: [TypeVarID: [TypeID]] = [:]
        var upperBounds: [TypeVarID: [TypeID]] = [:]
        var varRelations: [(left: TypeVarID, right: TypeVarID, blame: SourceRange?)] = []

        for variable in vars {
            lowerBounds[variable] = []
            upperBounds[variable] = []
        }

        for constraint in constraints {
            let relations = normalize(constraint)
            for relation in relations {
                switch (relation.left, relation.right) {
                case let (.type(leftType), .type(rightType)):
                    if !typeSystem.isSubtype(leftType, rightType) {
                        return failureSolution(vars: vars, typeSystem: typeSystem, blameRange: relation.blame)
                    }

                case let (.variable(variable), .type(boundType)):
                    appendUnique(boundType, to: &upperBounds[variable, default: []])

                case let (.type(boundType), .variable(variable)):
                    appendUnique(boundType, to: &lowerBounds[variable, default: []])

                case let (.variable(leftVar), .variable(rightVar)):
                    varRelations.append((leftVar, rightVar, relation.blame))
                }
            }
        }

        if !varRelations.isEmpty {
            for _ in 0..<max(1, vars.count) {
                var changed = false
                for relation in varRelations {
                    let leftVar = relation.left
                    let rightVar = relation.right

                    let rightUpper = upperBounds[rightVar, default: []]
                    for bound in rightUpper {
                        if appendUnique(bound, to: &upperBounds[leftVar, default: []]) {
                            changed = true
                        }
                    }

                    let leftLower = lowerBounds[leftVar, default: []]
                    for bound in leftLower {
                        if appendUnique(bound, to: &lowerBounds[rightVar, default: []]) {
                            changed = true
                        }
                    }
                }
                if !changed {
                    break
                }
            }
        }

        var substitution: [TypeVarID: TypeID] = [:]
        for variable in vars {
            let lowers = lowerBounds[variable, default: []]
            let uppers = upperBounds[variable, default: []]
            if lowers.isEmpty && uppers.isEmpty {
                substitution[variable] = typeSystem.errorType
                continue
            }

            let candidate: TypeID
            if lowers.isEmpty {
                candidate = typeSystem.greatestLowerBound(uppers)
            } else if uppers.isEmpty {
                candidate = typeSystem.leastUpperBound(lowers)
            } else {
                let lowerCandidate = typeSystem.leastUpperBound(lowers)
                let upperCandidate = typeSystem.greatestLowerBound(uppers)
                guard typeSystem.isSubtype(lowerCandidate, upperCandidate) else {
                    let blameRange = firstRelevantBlameRange(for: variable, relations: constraints)
                    let message = """
                    Conflicting bounds for type variable #\(variable.rawValue): \
                    inferred \(typeSystem.renderType(lowerCandidate)) is not a subtype of \(typeSystem.renderType(upperCandidate)). \
                    lower=[\(renderBounds(lowers, typeSystem: typeSystem))], upper=[\(renderBounds(uppers, typeSystem: typeSystem))]
                    """
                    return failureSolution(
                        vars: vars,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        message: message
                    )
                }
                candidate = lowerCandidate
            }

            if candidate == typeSystem.errorType {
                let blameRange = firstRelevantBlameRange(for: variable, relations: constraints)
                let message = """
                Failed to infer type variable #\(variable.rawValue) from bounds: \
                lower=[\(renderBounds(lowers, typeSystem: typeSystem))], upper=[\(renderBounds(uppers, typeSystem: typeSystem))]
                """
                return failureSolution(
                    vars: vars,
                    typeSystem: typeSystem,
                    blameRange: blameRange,
                    message: message
                )
            }
            substitution[variable] = candidate
        }

        for constraint in constraints {
            guard let left = resolve(constraint.left, substitution: substitution),
                  let right = resolve(constraint.right, substitution: substitution) else {
                return failureSolution(
                    vars: vars,
                    typeSystem: typeSystem,
                    blameRange: constraint.blameRange,
                    message: "Type inference left unresolved variables while checking constraints."
                )
            }
            let ok = isConstraintSatisfied(
                kind: constraint.kind,
                left: left,
                right: right,
                typeSystem: typeSystem
            )
            if !ok {
                let relation = relationOperator(for: constraint.kind)
                let message = "Type constraint is not satisfied: \(typeSystem.renderType(left)) \(relation) \(typeSystem.renderType(right))."
                return failureSolution(
                    vars: vars,
                    typeSystem: typeSystem,
                    blameRange: constraint.blameRange,
                    message: message
                )
            }
        }

        for variable in vars where substitution[variable] == nil {
            substitution[variable] = typeSystem.errorType
        }
        return Solution(substitution: substitution, isSuccess: true, failure: nil)
    }

    private func normalize(_ constraint: VariableConstraint) -> [(left: ConstraintOperand, right: ConstraintOperand, blame: SourceRange?)] {
        switch constraint.kind {
        case .subtype:
            return [(constraint.left, constraint.right, constraint.blameRange)]
        case .equal:
            return [
                (constraint.left, constraint.right, constraint.blameRange),
                (constraint.right, constraint.left, constraint.blameRange)
            ]
        case .supertype:
            return [(constraint.right, constraint.left, constraint.blameRange)]
        }
    }

    private func isConstraintSatisfied(
        kind: ConstraintKind,
        left: TypeID,
        right: TypeID,
        typeSystem: TypeSystem
    ) -> Bool {
        switch kind {
        case .subtype:
            return typeSystem.isSubtype(left, right)
        case .equal:
            return typeSystem.isSubtype(left, right) && typeSystem.isSubtype(right, left)
        case .supertype:
            return typeSystem.isSubtype(right, left)
        }
    }

    private func resolve(_ operand: ConstraintOperand, substitution: [TypeVarID: TypeID]) -> TypeID? {
        switch operand {
        case .type(let type):
            return type
        case .variable(let variable):
            return substitution[variable]
        }
    }

    @discardableResult
    private func appendUnique(_ value: TypeID, to array: inout [TypeID]) -> Bool {
        if array.contains(value) {
            return false
        }
        array.append(value)
        return true
    }

    private func firstRelevantBlameRange(
        for variable: TypeVarID,
        relations: [VariableConstraint]
    ) -> SourceRange? {
        for relation in relations {
            switch (relation.left, relation.right) {
            case (.variable(let lhs), _):
                if lhs == variable {
                    return relation.blameRange
                }
            case (_, .variable(let rhs)):
                if rhs == variable {
                    return relation.blameRange
                }
            default:
                continue
            }
        }
        return nil
    }

    private func failureSolution(
        vars: [TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?,
        message: String = "Type constraint could not be satisfied."
    ) -> Solution {
        var substitution: [TypeVarID: TypeID] = [:]
        for variable in vars {
            substitution[variable] = typeSystem.errorType
        }
        let diagnostic = Diagnostic(
            severity: .error,
            code: "KSWIFTK-TYPE-0001",
            message: message,
            primaryRange: blameRange,
            secondaryRanges: []
        )
        return Solution(substitution: substitution, isSuccess: false, failure: diagnostic)
    }

    private func relationOperator(for kind: ConstraintKind) -> String {
        switch kind {
        case .subtype:
            return "<:"
        case .equal:
            return "=="
        case .supertype:
            return ":>"
        }
    }

    private func renderBounds(_ bounds: [TypeID], typeSystem: TypeSystem) -> String {
        if bounds.isEmpty {
            return "-"
        }
        return bounds
            .map(typeSystem.renderType)
            .sorted()
            .joined(separator: ", ")
    }
}
