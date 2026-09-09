import RuntimeABI

enum MemberDispatchReceiverKind: String, Equatable, Hashable {
    case intRange
    case longRange
    case charRange
    case uintRange
    case ulongRange
    case intProgression
    case longProgression
    case charProgression
    case uintProgression
    case ulongProgression
    case iterable
    case list
    case set
    case collection
    case map
    case sequence
    case string
    case charSequence

    var isCharRangeLike: Bool {
        self == .charRange || self == .charProgression
    }

    var isLongRangeLike: Bool {
        self == .longRange || self == .longProgression
    }

    var isUIntRangeLike: Bool {
        self == .uintRange || self == .uintProgression
    }

    var isULongRangeLike: Bool {
        self == .ulongRange || self == .ulongProgression
    }
}

enum MemberDispatchLambdaShape: String, Equatable, Hashable {
    case none
    case hofLambda
}

enum MemberRuntimeArgumentMode: String, Equatable, Hashable {
    case lowered
    case normalized
}

enum MemberRuntimeThrownResultMode: String, Equatable, Hashable {
    case none
    case nullableAny
}

struct MemberRuntimeCallSpec: Equatable, Hashable {
    let runtimeLinkName: String
    let canThrow: Bool
    let argumentMode: MemberRuntimeArgumentMode
    let thrownResultMode: MemberRuntimeThrownResultMode

    init(
        runtimeLinkName: String,
        canThrow: Bool = false,
        argumentMode: MemberRuntimeArgumentMode = .lowered,
        thrownResultMode: MemberRuntimeThrownResultMode = .none
    ) {
        self.runtimeLinkName = runtimeLinkName
        self.canThrow = canThrow
        self.argumentMode = argumentMode
        self.thrownResultMode = thrownResultMode
    }
}

struct MemberDispatchKey: Equatable, Hashable, CustomStringConvertible {
    let receiverKind: MemberDispatchReceiverKind
    let memberName: String
    let arity: Int
    let lambdaShape: MemberDispatchLambdaShape

    init(
        receiverKind: MemberDispatchReceiverKind,
        memberName: String,
        arity: Int,
        lambdaShape: MemberDispatchLambdaShape = .none
    ) {
        self.receiverKind = receiverKind
        self.memberName = memberName
        self.arity = arity
        self.lambdaShape = lambdaShape
    }

    var description: String {
        return "\(receiverKind).\(memberName):\(arity) \(lambdaShape)"
    }
}

enum MemberRuntimeDispatch {
    static func rangeReceiverKind(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let nominalName: String? = {
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                return nil
            }
            return interner.resolve(symbol.name)
        }()

        switch nominalName {
        case "IntProgression":
            return .intProgression
        case "LongProgression":
            return .longProgression
        case "CharProgression":
            return .charProgression
        case "UIntProgression":
            return .uintProgression
        case "ULongProgression":
            return .ulongProgression
        case "IntRange":
            return .intRange
        case "LongRange":
            return .longRange
        case "CharRange":
            return .charRange
        case "UIntRange":
            return .uintRange
        case "ULongRange":
            return .ulongRange
        default:
            break
        }

        guard sema.bindings.isRangeExpr(receiverExpr) else {
            return nil
        }
        if sema.bindings.isCharRangeExpr(receiverExpr) {
            return .charRange
        }
        if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
            return .ulongRange
        }
        if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
            return .uintRange
        }
        if nonNullReceiverType == sema.types.longType {
            return .longRange
        }
        return .intRange
    }

    static func collectionReceiverKind(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch knownNames.collectionKind(of: symbol) {
        case .map?:
            return .map
        case .set?:
            return .set
        case .list?:
            return .list
        case .collection?:
            return .collection
        case .sequence?:
            return .sequence
        case .array?, nil:
            break
        }

        if symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
        {
            return .iterable
        }
        return nil
    }

    static func stringReceiverKind(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
            return .string
        }
        if let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
           case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
           classType.classSymbol == charSequenceSymbol
        {
            return .charSequence
        }
        return nil
    }

    static func rangeRuntimeLinkName(for key: MemberDispatchKey) -> String? {
        let kind = key.receiverKind

        // KSP-457: range random APIs are bundled Kotlin source wrappers. Their
        // private __kk_* calls are lowered from the source bodies, not from the
        // legacy member-dispatch table.
        if key.memberName == "random" || key.memberName == "randomOrNull" {
            return nil
        }

        switch key.memberName {
        case "contains":
            if kind.isULongRangeLike { return "kk_ulong_range_contains" }
            if kind.isUIntRangeLike { return "kk_uint_range_contains" }
            return "__kk_range_contains"
        case "isEmpty":
            return rangeRuntimeName(kind: kind, member: "isEmpty")
        case "endExclusive":
            return "__kk_range_endExclusive"
        case "sum":
            if kind.isUIntRangeLike { return "kk_uint_range_sum" }
            return "__kk_range_sum"
        case "count":
            return rangeRuntimeName(kind: kind, member: "count")
        case "toList":
            return rangeRuntimeName(
                kind: kind,
                member: "toList",
                longMember: "toList",
                charMember: "toList",
                charProgressionUsesChar: true
            )
        case "toUIntArray":
            return "kk_uint_range_toUIntArray"
        case "toULongArray":
            return "kk_ulong_range_toULongArray"
        case "toLongArray":
            return "kk_long_range_toLongArray"
        case "iterator":
            return rangeRuntimeName(kind: kind, member: "iterator", longMember: "iterator")
        case "forEach":
            return rangeRuntimeName(kind: kind, member: "forEach", longMember: "forEach")
        case "map":
            return rangeRuntimeName(kind: kind, member: "map", longMember: "map")
        case "mapIndexed":
            return rangeRuntimeName(kind: kind, member: "mapIndexed")
        case "mapNotNull":
            return rangeRuntimeName(kind: kind, member: "mapNotNull")
        case "filter":
            return rangeRuntimeName(kind: kind, member: "filter")
        case "filterIndexed":
            return rangeRuntimeName(kind: kind, member: "filterIndexed")
        case "filterNot":
            return rangeRuntimeName(kind: kind, member: "filterNot")
        case "reduce":
            return rangeRuntimeName(kind: kind, member: "reduce")
        case "reduceIndexed":
            return rangeRuntimeName(kind: kind, member: "reduceIndexed")
        case "fold":
            return rangeRuntimeName(kind: kind, member: "fold")
        case "foldIndexed":
            return rangeRuntimeName(kind: kind, member: "foldIndexed")
        case "find":
            return rangeRuntimeName(kind: kind, member: "find")
        case "findLast":
            return rangeRuntimeName(kind: kind, member: "findLast")
        case "first":
            if key.arity > 0 {
                return rangeRuntimeName(kind: kind, member: "first_predicate")
            }
            return rangeRuntimeName(kind: kind, member: "first", longMember: "first")
        case "start":
            return rangeRuntimeName(kind: kind, member: "first", longMember: "first")
        case "firstOrNull":
            if key.arity == 0 {
                return rangeRuntimeName(kind: kind, member: "firstOrNull", longMember: "firstOrNull")
            }
            return rangeRuntimeName(kind: kind, member: "firstOrNull_predicate")
        case "last":
            if key.arity > 0 {
                return rangeRuntimeName(kind: kind, member: "last_predicate")
            }
            return rangeRuntimeName(kind: kind, member: "last", longMember: "last")
        case "end":
            return rangeRuntimeName(kind: kind, member: "last", longMember: "last")
        case "lastOrNull":
            if key.arity == 0 {
                return rangeRuntimeName(kind: kind, member: "lastOrNull", longMember: "lastOrNull")
            }
            return rangeRuntimeName(kind: kind, member: "lastOrNull_predicate")
        case "any":
            return rangeRuntimeName(kind: kind, member: "any")
        case "all":
            return rangeRuntimeName(kind: kind, member: "all")
        case "none":
            return rangeRuntimeName(kind: kind, member: "none")
        case "chunked":
            return rangeRuntimeName(kind: kind, member: "chunked")
        case "windowed":
            return rangeRuntimeName(kind: kind, member: "windowed")
        case "take":
            return rangeRuntimeName(kind: kind, member: "take", longMember: "take", charMember: "take")
        case "drop":
            return rangeRuntimeName(kind: kind, member: "drop", longMember: "drop", charMember: "drop")
        case "average":
            return rangeRuntimeName(kind: kind, member: "average", longMember: "average")
        case "sorted":
            return rangeRuntimeName(kind: kind, member: "sorted", longMember: "sorted", charMember: "sorted")
        case "reversed":
            return rangeRuntimeName(kind: kind, member: "reversed")
        case "step":
            if key.arity == 0 {
                return rangeRuntimeName(
                    kind: kind,
                    member: "step",
                    longMember: "step",
                    charMember: "step",
                    charProgressionUsesChar: true
                )
            }
            if kind.isULongRangeLike { return "__kk_ulong_step" }
            if kind.isUIntRangeLike { return nil }
            if kind.isCharRangeLike { return "__kk_char_range_step" }
            return "__kk_op_step"
        default:
            return nil
        }
    }

    static func collectionRuntimeLinkName(for key: MemberDispatchKey) -> String? {
        guard let ownerKind = stdlibSurfaceOwnerKind(for: key.receiverKind) else {
            return nil
        }
        return StdlibSurfaceSpec.collectionHOFMember(
            ownerKind: ownerKind,
            memberName: key.memberName,
            arity: key.arity
        )?.runtimeLinkName
    }

    static func stringRuntimeCall(for key: MemberDispatchKey) -> MemberRuntimeCallSpec? {
        guard key.receiverKind == .string else {
            return nil
        }

        switch (key.memberName, key.arity) {
        case ("lowercase", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lowercase_flat")
        case ("uppercase", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_uppercase_flat")
        case ("toDouble", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toDouble_flat", canThrow: true)
        case ("toDoubleOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toDoubleOrNull_flat")
        case ("toFloatOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toFloatOrNull_flat")
        case ("toRegex", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toRegex_flat")
        case ("firstOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_firstOrNull_flat")
        case ("lastOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lastOrNull_flat")
        case ("get", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_get_flat")
        case ("compareTo", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_compareTo_flat")
        case ("matches", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_matches_regex_flat")
        case ("encodeToByteArray", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_encodeToByteArray_charset_flat")
        case ("toByteArray", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toByteArray_charset_flat")

        default:
            return nil
        }
    }

    private static func rangeRuntimeName(
        kind: MemberDispatchReceiverKind,
        member: String,
        longMember: String? = nil,
        charMember: String? = nil,
        charProgressionUsesChar: Bool = false
    ) -> String? {
        if kind == .charRange || (kind == .charProgression && charProgressionUsesChar), let charMember {
            return "kk_char_range_\(charMember)"
        }
        if kind.isULongRangeLike {
            return "kk_ulong_range_\(member)"
        }
        if kind == .uintRange {
            let sourceBacked: Set<String> = [
                "iterator", "chunked", "windowed", "take", "drop",
                "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot",
                "forEach",
                "reduce", "reduceIndexed", "fold", "foldIndexed",
                "find", "findLast",
                "first_predicate", "firstOrNull_predicate",
                "last_predicate", "lastOrNull_predicate",
                "any", "all", "none",
            ]
            if sourceBacked.contains(member) {
                return nil
            }
        }
        if kind == .uintProgression {
            let sourceBacked: Set<String> = [
                "first", "firstOrNull", "last", "lastOrNull",
                "iterator", "chunked", "windowed", "take", "drop",
                "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot",
            ]
            if sourceBacked.contains(member) {
                return nil
            }
        }
        if kind.isUIntRangeLike {
            return "kk_uint_range_\(member)"
        }

        // KSP-453: IntRange/IntProgression HOFs are now implemented in bundled
        // Kotlin source (RangeHOF.kt) and must not be routed to the legacy
        // kk_range_* runtime entry points.
        if kind == .intRange || kind == .intProgression {
            let sourceBacked: Set<String> = [
                "toList", "toIntArray", "forEach", "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot",
                "reduce", "reduceIndexed", "fold", "foldIndexed",
                "find", "findLast",
                "first_predicate", "firstOrNull", "firstOrNull_predicate",
                "last_predicate", "lastOrNull", "lastOrNull_predicate",
                "any", "all", "none",
                "chunked", "windowed",
                "take", "drop", "average", "sorted",
            ]
            if sourceBacked.contains(member) {
                return nil
            }
        }

        if kind == .longProgression {
            let sourceBacked: Set<String> = ["first", "firstOrNull", "last", "lastOrNull"]
            if sourceBacked.contains(member) {
                return nil
            }
        }

        if kind == .ulongProgression {
            let sourceBacked: Set<String> = ["first", "firstOrNull", "last", "lastOrNull"]
            if sourceBacked.contains(member) {
                return nil
            }
        }

        let migratedRangeMembers: Set<String> = ["first", "last", "count", "isEmpty", "reversed"]
        if migratedRangeMembers.contains(member) && !kind.isULongRangeLike && !kind.isUIntRangeLike {
            return "__kk_range_\(member)"
        }
        if kind.isLongRangeLike, let longMember {
            return "kk_long_range_\(longMember)"
        }
        return "kk_range_\(member)"
    }

    private static func stdlibSurfaceOwnerKind(
        for receiverKind: MemberDispatchReceiverKind
    ) -> StdlibSurfaceOwnerKind? {
        switch receiverKind {
        case .map:
            return .map
        case .sequence:
            return .sequence
        case .iterable, .list, .set, .collection:
            return .list
        default:
            return nil
        }
    }
}
