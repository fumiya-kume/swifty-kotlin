public struct TypeVarID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
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
        var substitution: [TypeVarID: TypeID] = [:]
        for variable in vars {
            substitution[variable] = typeSystem.errorType
        }

        for constraint in constraints {
            let ok: Bool
            switch constraint.kind {
            case .subtype:
                ok = typeSystem.isSubtype(constraint.left, constraint.right)
            case .equal:
                ok = typeSystem.isSubtype(constraint.left, constraint.right)
                    && typeSystem.isSubtype(constraint.right, constraint.left)
            case .supertype:
                ok = typeSystem.isSubtype(constraint.right, constraint.left)
            }

            if !ok {
                let diagnostic = Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-TYPE-0001",
                    message: "Type constraint could not be satisfied.",
                    primaryRange: constraint.blameRange,
                    secondaryRanges: []
                )
                return Solution(substitution: substitution, isSuccess: false, failure: diagnostic)
            }
        }

        return Solution(substitution: substitution, isSuccess: true, failure: nil)
    }
}
