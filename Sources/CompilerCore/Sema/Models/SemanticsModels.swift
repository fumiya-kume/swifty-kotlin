// swiftlint:disable file_length
public struct SymbolID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = SymbolID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum SymbolKind: Hashable, Sendable {
    case package
    case `class`
    case interface
    case object
    case enumClass
    case annotationClass
    case typeAlias
    case function
    case constructor
    case property
    case field
    case backingField
    case typeParameter
    case valueParameter
    case local
    case label
}

public struct SymbolFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let suspendFunction = SymbolFlags(rawValue: 1 << 0)
    public static let inlineFunction = SymbolFlags(rawValue: 1 << 1)
    public static let mutable = SymbolFlags(rawValue: 1 << 2)
    public static let synthetic = SymbolFlags(rawValue: 1 << 3)
    public static let `static` = SymbolFlags(rawValue: 1 << 4)
    public static let sealedType = SymbolFlags(rawValue: 1 << 5)
    public static let dataType = SymbolFlags(rawValue: 1 << 6)
    public static let reifiedTypeParameter = SymbolFlags(rawValue: 1 << 7)
    public static let innerClass = SymbolFlags(rawValue: 1 << 8)
    public static let valueType = SymbolFlags(rawValue: 1 << 9)
    public static let operatorFunction = SymbolFlags(rawValue: 1 << 10)
    public static let constValue = SymbolFlags(rawValue: 1 << 11)
    public static let abstractType = SymbolFlags(rawValue: 1 << 12)
    public static let openType = SymbolFlags(rawValue: 1 << 13)
    public static let overrideMember = SymbolFlags(rawValue: 1 << 14)
    public static let finalMember = SymbolFlags(rawValue: 1 << 15)
    public static let funInterface = SymbolFlags(rawValue: 1 << 16)
    public static let expectDeclaration = SymbolFlags(rawValue: 1 << 17)
    public static let actualDeclaration = SymbolFlags(rawValue: 1 << 18)
    public static let lateinitProperty = SymbolFlags(rawValue: 1 << 19)
    /// Marks a synthetic stub function as one that passes an outThrown pointer
    /// to signal ArithmeticException / NumberFormatException at runtime.
    /// The ABI lowering pass must NOT add this symbol to nonThrowingCallees.
    public static let throwingFunction = SymbolFlags(rawValue: 1 << 20)
    public static let readOnlyProperty = SymbolFlags(rawValue: 1 << 21)
}

public struct SemanticSymbol: Sendable {
    public let id: SymbolID
    public let kind: SymbolKind
    public let name: InternedString
    public let fqName: [InternedString]
    public let declSite: SourceRange?
    public let visibility: Visibility
    public var flags: SymbolFlags
}

func isCompatibleExpectActualPair(
    newKind: SymbolKind,
    newFlags: SymbolFlags,
    existing: SemanticSymbol
) -> Bool {
    let isNewExpect = newFlags.contains(.expectDeclaration)
    let isNewActual = newFlags.contains(.actualDeclaration)
    guard isNewExpect != isNewActual else {
        return false
    }

    let hasExistingExpect = existing.flags.contains(.expectDeclaration)
    let hasExistingActual = existing.flags.contains(.actualDeclaration)
    guard hasExistingExpect != hasExistingActual else {
        return false
    }

    if isNewExpect {
        guard hasExistingActual else {
            return false
        }
        return newKind == existing.kind
            || (newKind == .annotationClass && existing.kind == .typeAlias)
    }

    guard hasExistingExpect else {
        return false
    }
    return newKind == existing.kind
        || (newKind == .typeAlias && existing.kind == .annotationClass)
}

public struct FunctionSignature: Hashable, Sendable {
    public let receiverType: TypeID?
    public let parameterTypes: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let canThrow: Bool
    public let valueParameterSymbols: [SymbolID]
    public let valueParameterHasDefaultValues: [Bool]
    public let valueParameterIsVararg: [Bool]
    public let typeParameterSymbols: [SymbolID]
    public let reifiedTypeParameterIndices: Set<Int>
    public let typeParameterUpperBounds: [TypeID?]
    public let typeParameterUpperBoundsList: [[TypeID]]
    /// Number of leading entries in `typeParameterSymbols` that belong to the
    /// enclosing class/interface (not the function itself).  The overload resolver
    /// skips these when matching explicit type arguments and offsetting reified
    /// indices.  Defaults to 0 for non-member or non-generic-class functions.
    public let classTypeParameterCount: Int

    public init(
        receiverType: TypeID? = nil,
        parameterTypes: [TypeID],
        returnType: TypeID,
        isSuspend: Bool = false,
        canThrow: Bool = false,
        valueParameterSymbols: [SymbolID] = [],
        valueParameterHasDefaultValues: [Bool] = [],
        valueParameterIsVararg: [Bool] = [],
        typeParameterSymbols: [SymbolID] = [],
        reifiedTypeParameterIndices: Set<Int> = [],
        typeParameterUpperBounds: [TypeID?] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        classTypeParameterCount: Int = 0
    ) {
        self.receiverType = receiverType
        self.parameterTypes = parameterTypes
        self.returnType = returnType
        self.isSuspend = isSuspend
        self.canThrow = canThrow
        self.valueParameterSymbols = valueParameterSymbols
        self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
        self.valueParameterIsVararg = valueParameterIsVararg
        self.typeParameterSymbols = typeParameterSymbols
        self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
        let normalizedUpperBoundsList: [[TypeID]] = if !typeParameterUpperBoundsList.isEmpty {
            typeParameterUpperBoundsList
        } else {
            typeParameterUpperBounds.map { bound in
                bound.map { [$0] } ?? []
            }
        }
        self.typeParameterUpperBoundsList = normalizedUpperBoundsList
        self.typeParameterUpperBounds = normalizedUpperBoundsList.map(\.first)
        self.classTypeParameterCount = classTypeParameterCount
    }
}

public struct ContractNonNullEffect: Equatable, Sendable {
    public let parameterSymbol: SymbolID
    public let appliesOnAnyReturn: Bool

    public init(parameterSymbol: SymbolID, appliesOnAnyReturn: Bool) {
        self.parameterSymbol = parameterSymbol
        self.appliesOnAnyReturn = appliesOnAnyReturn
    }
}

/// Represents a `contract { returns() }` or `contract { returns(true/false) }` effect
/// indicating the function guarantees normal return (optionally with a specific Boolean
/// return value).
///
/// - Bare `returns()`: the function guarantees it will return normally (not throw).
/// - `returns(true)` / `returns(false)`: the function guarantees its *return value*
///   will be the given Boolean constant on normal completion.
///
/// Models the kind of `returns(...)` contract effect.
///
/// - `returnsNormally`: bare `returns()` -- the function guarantees normal return.
/// - `returnsBooleanValue(Bool, conditionParameterIndex: Int?)`: `returns(true)` or
///   `returns(false)` -- the function guarantees a specific Boolean return value on
///   normal completion.  `conditionParameterIndex` is a heuristic to locate the first
///   Boolean parameter for downstream smart-cast patterns like `require(condition)`.
public enum ContractReturnsEffect: Equatable, Sendable {
    /// Bare `returns()` -- the function guarantees normal return without specifying
    /// a particular return value.
    case returnsNormally
    /// `returns(true)` or `returns(false)` -- the function guarantees a specific
    /// Boolean return value on normal completion.
    /// - `expectedValue`: the Boolean value the function returns (`true` or `false`).
    /// - `conditionParameterIndex`: heuristic index of the first Boolean parameter,
    ///   used by downstream smart-cast analysis (e.g. `require(condition)` patterns).
    ///   May be nil if no Boolean parameter exists.
    case returnsBooleanValue(expectedValue: Bool, conditionParameterIndex: Int?)
}

/// STDLIB-592: `contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }` effect.
/// Records that a lambda parameter is guaranteed to be invoked a specific number of times.
public struct ContractCallsInPlaceEffect: Equatable, Sendable {
    public let parameterSymbol: SymbolID
    public let kind: InvocationKind

    public init(parameterSymbol: SymbolID, kind: InvocationKind) {
        self.parameterSymbol = parameterSymbol
        self.kind = kind
    }
}

/// Kotlin `InvocationKind` enum modelling how many times a lambda parameter is called.
public enum InvocationKind: String, Equatable, Sendable {
    case atMostOnce = "AT_MOST_ONCE"
    case atLeastOnce = "AT_LEAST_ONCE"
    case exactlyOnce = "EXACTLY_ONCE"
    case unknown = "UNKNOWN"
}

/// STDLIB-591: `contract { returns() implies (condition) }` effect where `condition`
/// is a Boolean parameter.  After normal return, the argument expression at
/// `conditionParameterIndex` is guaranteed true, enabling smart casts derived from
/// that expression (e.g. `require(x != null)` narrows `x` to non-null).
public struct ContractConditionEffect: Equatable, Sendable {
    /// Index into the function signature's value-parameter list whose argument
    /// expression is guaranteed true on normal return.
    public let conditionParameterIndex: Int

    /// When to apply the smart cast:
    /// - `nil`: applies on any normal return (`returns() implies condition`)
    /// - `true`: applies when function returns true (`returns(true) implies condition`)
    /// - `false`: applies when function returns false (`returns(false) implies condition`)
    public let returnsValue: Bool?

    public init(conditionParameterIndex: Int, returnsValue: Bool? = nil) {
        self.conditionParameterIndex = conditionParameterIndex
        self.returnsValue = returnsValue
    }
}

/// STDLIB-593: `contract { returnsNotNull() }` effect.
/// Records that the function is guaranteed to return a non-null value.
public struct ContractReturnsNotNullEffect: Equatable, Sendable {
    public init() {}
}

public struct NominalLayout: Equatable, Sendable {
    public let objectHeaderWords: Int
    public let instanceFieldCount: Int
    public let instanceSizeWords: Int
    public let fieldOffsets: [SymbolID: Int]
    public let vtableSlots: [SymbolID: Int]
    public let itableSlots: [SymbolID: Int]
    public let vtableSize: Int
    public let itableSize: Int
    public let superClass: SymbolID?

    public init(
        objectHeaderWords: Int,
        instanceFieldCount: Int,
        instanceSizeWords: Int,
        fieldOffsets: [SymbolID: Int] = [:],
        vtableSlots: [SymbolID: Int],
        itableSlots: [SymbolID: Int],
        vtableSize: Int? = nil,
        itableSize: Int? = nil,
        superClass: SymbolID?
    ) {
        self.objectHeaderWords = objectHeaderWords
        let inferredFieldCount = max(0, fieldOffsets.count)
        self.instanceFieldCount = max(instanceFieldCount, inferredFieldCount)
        let inferredInstanceSizeWords = max(0, (fieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1)
        self.instanceSizeWords = max(
            max(instanceSizeWords, inferredInstanceSizeWords),
            objectHeaderWords + self.instanceFieldCount
        )
        self.fieldOffsets = fieldOffsets
        self.vtableSlots = vtableSlots
        self.itableSlots = itableSlots
        let inferredVtableSize = (vtableSlots.values.max() ?? -1) + 1
        let inferredItableSize = (itableSlots.values.max() ?? -1) + 1
        self.vtableSize = max(0, max(vtableSize ?? 0, inferredVtableSize))
        self.itableSize = max(0, max(itableSize ?? 0, inferredItableSize))
        self.superClass = superClass
    }
}

public struct NominalLayoutHint: Equatable, Sendable {
    public let declaredFieldCount: Int?
    public let declaredInstanceSizeWords: Int?
    public let declaredVtableSize: Int?
    public let declaredItableSize: Int?

    public init(
        declaredFieldCount: Int?,
        declaredInstanceSizeWords: Int?,
        declaredVtableSize: Int?,
        declaredItableSize: Int?
    ) {
        self.declaredFieldCount = declaredFieldCount
        self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
    }
}

public protocol Scope: AnyObject {
    var parent: Scope? { get }
    func lookup(_ name: InternedString) -> [SymbolID]
    func insert(_ sym: SymbolID)
}

open class BaseScope: Scope {
    public let parent: Scope?
    private let symbols: SymbolTable
    private var locals: [InternedString: [SymbolID]] = [:]

    public init(parent: Scope?, symbols: SymbolTable) {
        self.parent = parent
        self.symbols = symbols
    }

    open func lookup(_ name: InternedString) -> [SymbolID] {
        if let local = locals[name], !local.isEmpty {
            return local
        }
        return parent?.lookup(name) ?? []
    }

    open func insert(_ sym: SymbolID) {
        guard let symbol = symbols.symbol(sym) else {
            return
        }
        var bucket = locals[symbol.name, default: []]
        if !bucket.contains(sym) {
            bucket.append(sym)
        }
        locals[symbol.name] = bucket
    }

    open func insertWithAlias(_ sym: SymbolID, asName: InternedString) {
        var bucket = locals[asName, default: []]
        if !bucket.contains(sym) {
            bucket.append(sym)
        }
        locals[asName] = bucket
    }
}

public final class FileScope: BaseScope {}
public final class PackageScope: BaseScope {}
public final class ImportScope: BaseScope {}

public final class ClassMemberScope: BaseScope {
    private let ownerSymbol: SymbolID
    private let thisType: TypeID?

    public init(parent: Scope?, symbols: SymbolTable, ownerSymbol: SymbolID, thisType: TypeID?) {
        self.ownerSymbol = ownerSymbol
        self.thisType = thisType
        super.init(parent: parent, symbols: symbols)
    }

    public var receiverType: TypeID? {
        thisType
    }

    public var owner: SymbolID {
        ownerSymbol
    }
}

public final class FunctionScope: BaseScope {}
public final class BlockScope: BaseScope {}

import Foundation

public final class SymbolTable {
    private var symbolsStorage: [SemanticSymbol] = []
    private var byFQName: [[InternedString]: [SymbolID]] = [:]
    private var byShortName: [InternedString: [SymbolID]] = [:]
    private var byKind: [SymbolKind: [SymbolID]] = [:]
    private var byParentFQName: [[InternedString]: [SymbolID]] = [:]
    private var byDeclSite: [SourceRange: [SymbolID]] = [:]
    private var functionSignatures: [SymbolID: FunctionSignature] = [:]
    private var propertyTypes: [SymbolID: TypeID] = [:]
    private var directSupertypes: [SymbolID: [SymbolID]] = [:]
    private var supertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]
    private var nominalLayouts: [SymbolID: NominalLayout] = [:]
    private var nominalLayoutHints: [SymbolID: NominalLayoutHint] = [:]
    private var externalLinkNames: [SymbolID: String] = [:]
    private var typeAliasUnderlyingTypes: [SymbolID: TypeID] = [:]
    private var typeAliasTypeParameters: [SymbolID: [SymbolID]] = [:]
    private var parentSymbols: [SymbolID: SymbolID] = [:]
    private var backingFieldSymbols: [SymbolID: SymbolID] = [:]
    private var delegateStorageSymbols: [SymbolID: SymbolID] = [:]
    private var delegateGetValueSymbols: [SymbolID: SymbolID] = [:]
    private var delegateSetValueSymbols: [SymbolID: SymbolID] = [:]
    private var delegateProvideDelegateSymbols: [SymbolID: SymbolID] = [:]
    private var accessorOwnerProperties: [SymbolID: SymbolID] = [:]
    private var extensionPropertyReceiverTypes: [SymbolID: TypeID] = [:]
    private var extensionPropertyGetterAccessors: [SymbolID: SymbolID] = [:]
    private var extensionPropertySetterAccessors: [SymbolID: SymbolID] = [:]
    private var typeParameterUpperBoundsMap: [SymbolID: [TypeID]] = [:]
    private var sourceFileIDs: [SymbolID: FileID] = [:]
    private var annotationsStorage: [SymbolID: [MetadataAnnotationRecord]] = [:]
    private var companionObjectSymbols: [SymbolID: SymbolID] = [:]
    private var valueClassUnderlyingTypes: [SymbolID: TypeID] = [:]
    private var sealedSubclassesStorage: [SymbolID: [SymbolID]] = [:]
    private var constValueExprKinds: [SymbolID: KIRExprKind] = [:]
    private var delegateHasProvideDelegate: Set<SymbolID> = []
    private var expectActualLinks: [SymbolID: SymbolID] = [:]
    private var contractNonNullEffects: [SymbolID: ContractNonNullEffect] = [:]
    private var contractReturnsEffects: [SymbolID: ContractReturnsEffect] = [:]
    private var contractCallsInPlaceEffects: [SymbolID: [ContractCallsInPlaceEffect]] = [:]
    private var contractReturnsNotNullEffects: Set<SymbolID> = []
    private var contractConditionEffects: [SymbolID: ContractConditionEffect] = [:]
    /// CLASS-008: Interfaces delegated by a class via `: Interface by expr`.
    /// Key = class symbol, Value = set of interface symbols that class delegates to.
    private var delegatedInterfacesByClass: [SymbolID: Set<SymbolID>] = [:]
    
    /// Thread safety lock for concurrent access
    private let lock = NSLock()

    public init() {}

    public var count: Int {
        symbolsStorage.count
    }

    public func allSymbols() -> [SemanticSymbol] {
        symbolsStorage
    }

    public func symbol(_ id: SymbolID) -> SemanticSymbol? {
        let index = Int(id.rawValue)
        guard index >= 0, index < symbolsStorage.count else {
            return nil
        }
        return symbolsStorage[index]
    }

    public func insertFlags(_ flags: SymbolFlags, for symbol: SymbolID) {
        let index = Int(symbol.rawValue)
        guard index >= 0, index < symbolsStorage.count else {
            return
        }
        symbolsStorage[index].flags.formUnion(flags)
    }

    public func lookup(fqName: [InternedString]) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return byFQName[fqName]?.first
    }

    public func lookupAll(fqName: [InternedString]) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        return byFQName[fqName] ?? []
    }

    public func lookupByShortName(_ name: InternedString) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        return byShortName[name] ?? []
    }

    public func define(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange?,
        visibility: Visibility,
        flags: SymbolFlags = []
    ) -> SymbolID {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = byFQName[fqName], !existing.isEmpty {
            let existingSymbols = existing.compactMap { symbol($0) }
            let existingKinds = existingSymbols.map(\.kind)

            let shouldCoexist = canCoexistAsOverload(kind: kind, existingKinds: existingKinds)
                || canCoexistAsExpectActual(kind: kind, flags: flags, existingSymbols: existingSymbols)
                || canCoexistAsSyntheticPropertyFamily(kind: kind, flags: flags, existingSymbols: existingSymbols)
            if shouldCoexist {
                return appendNewSymbol(
                    kind: kind,
                    name: name,
                    fqName: fqName,
                    declSite: declSite,
                    visibility: visibility,
                    flags: flags
                )
            }
            return existing[0]
        }
        return appendNewSymbol(
            kind: kind,
            name: name,
            fqName: fqName,
            declSite: declSite,
            visibility: visibility,
            flags: flags
        )
    }

    private func appendNewSymbol(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange?,
        visibility: Visibility,
        flags: SymbolFlags
    ) -> SymbolID {
        let id = SymbolID(rawValue: Int32(symbolsStorage.count))
        let symbol = SemanticSymbol(
            id: id,
            kind: kind,
            name: name,
            fqName: fqName,
            declSite: declSite,
            visibility: visibility,
            flags: flags
        )
        symbolsStorage.append(symbol)
        byFQName[fqName, default: []].append(id)
        byShortName[name, default: []].append(id)
        byKind[kind, default: []].append(id)
        if fqName.count >= 1 {
            let parentFQ = Array(fqName.dropLast())
            byParentFQName[parentFQ, default: []].append(id)
        }
        if let site = declSite {
            byDeclSite[site, default: []].append(id)
        }
        return id
    }

    private func canCoexistAsOverload(kind: SymbolKind, existingKinds: [SymbolKind]) -> Bool {
        func isCallableLike(_ kind: SymbolKind) -> Bool {
            switch kind {
            case .function, .constructor:
                true
            default:
                false
            }
        }
        if kind == .package {
            return true
        }
        let existingNonPackageKinds = existingKinds.filter { $0 != .package }
        if existingNonPackageKinds.isEmpty {
            return true
        }
        if kind == .property {
            return existingNonPackageKinds.allSatisfy { isCallableLike($0) }
                && !existingNonPackageKinds.contains(.property)
        }
        if isCallableLike(kind) {
            // Allow functions/constructors to coexist with nominal types
            // (class, enumClass, interface) — Kotlin supports factory
            // functions with the same name as a class (e.g. Regex(pattern)).
            // Kotlin also permits callable declarations to share a name with a
            // property, such as `var port` and `fun port(value: Int)`.
            return existingNonPackageKinds.allSatisfy {
                isCallableLike($0) || isNominalType($0) || $0 == .property
            }
        }
        guard isOverloadable(kind) else {
            return false
        }
        return existingNonPackageKinds.allSatisfy { isOverloadable($0) }
    }

    private func canCoexistAsExpectActual(
        kind: SymbolKind,
        flags: SymbolFlags,
        existingSymbols: [SemanticSymbol]
    ) -> Bool {
        // Allow exactly one matching `expect`/`actual` partner at a given FQ name.
        let existingNonPackage = existingSymbols.filter { $0.kind != .package }
        guard existingNonPackage.count == 1, let existing = existingNonPackage.first else {
            return false
        }
        return isCompatibleExpectActualPair(newKind: kind, newFlags: flags, existing: existing)
    }

    private func canCoexistAsSyntheticPropertyFamily(
        kind: SymbolKind,
        flags: SymbolFlags,
        existingSymbols: [SemanticSymbol]
    ) -> Bool {
        guard kind == .property, flags.contains(.synthetic) else {
            return false
        }
        let existingNonPackageSymbols = existingSymbols.filter { $0.kind != .package }
        guard !existingNonPackageSymbols.isEmpty else {
            return false
        }
        return existingNonPackageSymbols.allSatisfy { symbol in
            symbol.kind == .property && symbol.flags.contains(.synthetic)
        }
    }

    private func isOverloadable(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    private func isNominalType(_ kind: SymbolKind) -> Bool {
        kind == .class || kind == .enumClass || kind == .interface
    }

    public func setFunctionSignature(_ signature: FunctionSignature, for symbol: SymbolID) {
        functionSignatures[symbol] = signature
    }

    public func functionSignature(for symbol: SymbolID) -> FunctionSignature? {
        functionSignatures[symbol]
    }

    public func setPropertyType(_ type: TypeID, for symbol: SymbolID) {
        propertyTypes[symbol] = type
    }

    public func propertyType(for symbol: SymbolID) -> TypeID? {
        propertyTypes[symbol]
    }

    public func setDirectSupertypes(_ supertypes: [SymbolID], for symbol: SymbolID) {
        directSupertypes[symbol] = supertypes
    }

    public func directSupertypes(for symbol: SymbolID) -> [SymbolID] {
        directSupertypes[symbol] ?? []
    }

    public func setSupertypeTypeArgs(_ args: [TypeArg], for child: SymbolID, supertype parent: SymbolID) {
        supertypeTypeArgsMap[child, default: [:]][parent] = args
    }

    public func supertypeTypeArgs(for child: SymbolID, supertype parent: SymbolID) -> [TypeArg] {
        supertypeTypeArgsMap[child]?[parent] ?? []
    }

    public func directSubtypes(of symbol: SymbolID) -> [SymbolID] {
        var result: [SymbolID] = []
        for (candidate, supertypes) in directSupertypes where supertypes.contains(symbol) {
            result.append(candidate)
        }
        return result.sorted(by: { $0.rawValue < $1.rawValue })
    }

    /// CLASS-008: Record that a class delegates to an interface.
    public func addDelegatedInterface(_ interfaceSymbol: SymbolID, forClass classSymbol: SymbolID) {
        delegatedInterfacesByClass[classSymbol, default: []].insert(interfaceSymbol)
    }

    /// CLASS-008: Return the set of interface symbols that a class delegates to.
    public func delegatedInterfaces(forClass classSymbol: SymbolID) -> Set<SymbolID> {
        delegatedInterfacesByClass[classSymbol] ?? []
    }

    /// CLASS-008: Map from (classSymbol, interfaceSymbol) to the delegate field symbol.
    private var classDelegationFieldByClassAndInterface: [SymbolID: [SymbolID: SymbolID]] = [:]

    /// CLASS-008: Record the delegate field symbol for a class delegating to an interface.
    public func setClassDelegationField(
        _ fieldSymbol: SymbolID, forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID
    ) {
        classDelegationFieldByClassAndInterface[classSymbol, default: [:]][interfaceSymbol] = fieldSymbol
    }

    /// CLASS-008: Get the delegate field symbol for a class delegating to an interface.
    public func classDelegationField(forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID) -> SymbolID? {
        classDelegationFieldByClassAndInterface[classSymbol]?[interfaceSymbol]
    }

    /// CLASS-008: Map from (classSymbol, interfaceSymbol) to the delegate expression DeclID for lowering.
    private var classDelegationExprByClassAndInterface: [SymbolID: [SymbolID: ExprID]] = [:]

    /// CLASS-008: Record the delegate expression for a class delegating to an interface.
    public func setClassDelegationExpr(
        _ exprID: ExprID, forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID
    ) {
        classDelegationExprByClassAndInterface[classSymbol, default: [:]][interfaceSymbol] = exprID
    }

    /// CLASS-008: Get the delegate expression for a class delegating to an interface.
    public func classDelegationExpr(forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID) -> ExprID? {
        classDelegationExprByClassAndInterface[classSymbol]?[interfaceSymbol]
    }

    /// CLASS-008: Synthetic forwarding method symbols created for class delegation.
    /// Maps forwarding method symbol -> (interfaceSymbol, interfaceMethodSymbol, fieldSymbol).
    private var classDelegationForwardingMethodInfo: [SymbolID: (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)] = [:]

    /// CLASS-008: Per-class list of synthetic forwarding method symbols.
    private var classDelegationForwardingMethodsByClass: [SymbolID: [SymbolID]] = [:]

    /// CLASS-008: Record a synthetic forwarding method for class delegation.
    public func addClassDelegationForwardingMethod(
        _ forwardingSymbol: SymbolID,
        forClass classSymbol: SymbolID,
        interface interfaceSymbol: SymbolID,
        interfaceMethod interfaceMethodSymbol: SymbolID,
        field fieldSymbol: SymbolID
    ) {
        classDelegationForwardingMethodInfo[forwardingSymbol] = (interfaceSymbol, interfaceMethodSymbol, fieldSymbol)
        classDelegationForwardingMethodsByClass[classSymbol, default: []].append(forwardingSymbol)
    }

    /// CLASS-008: Get synthetic forwarding method symbols for a class.
    public func classDelegationForwardingMethodSymbols(forClass classSymbol: SymbolID) -> [SymbolID] {
        classDelegationForwardingMethodsByClass[classSymbol] ?? []
    }

    /// CLASS-008: Get the info needed to emit the forwarding body for a synthetic method.
    public func classDelegationForwardingMethodInfo(for forwardingSymbol: SymbolID) -> (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)? {
        classDelegationForwardingMethodInfo[forwardingSymbol]
    }

    public func setNominalLayout(_ layout: NominalLayout, for symbol: SymbolID) {
        nominalLayouts[symbol] = layout
    }

    public func nominalLayout(for symbol: SymbolID) -> NominalLayout? {
        nominalLayouts[symbol]
    }

    public func setNominalLayoutHint(_ hint: NominalLayoutHint, for symbol: SymbolID) {
        nominalLayoutHints[symbol] = hint
    }

    public func nominalLayoutHint(for symbol: SymbolID) -> NominalLayoutHint? {
        nominalLayoutHints[symbol]
    }

    public func setExternalLinkName(_ linkName: String, for symbol: SymbolID) {
        externalLinkNames[symbol] = linkName
    }

    public func externalLinkName(for symbol: SymbolID) -> String? {
        externalLinkNames[symbol]
    }

    public func setTypeAliasUnderlyingType(_ type: TypeID, for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        typeAliasUnderlyingTypes[symbol] = type
    }

    public func typeAliasUnderlyingType(for symbol: SymbolID) -> TypeID? {
        lock.lock()
        defer { lock.unlock() }
        return typeAliasUnderlyingTypes[symbol]
    }

    public func setTypeAliasTypeParameters(_ params: [SymbolID], for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        typeAliasTypeParameters[symbol] = params
    }

    public func typeAliasTypeParameters(for symbol: SymbolID) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        return typeAliasTypeParameters[symbol] ?? []
    }

    public func setParentSymbol(_ parent: SymbolID, for child: SymbolID) {
        parentSymbols[child] = parent
    }

    public func parentSymbol(for child: SymbolID) -> SymbolID? {
        parentSymbols[child]
    }

    public func setBackingFieldSymbol(_ backingField: SymbolID, for property: SymbolID) {
        backingFieldSymbols[property] = backingField
    }

    public func backingFieldSymbol(for property: SymbolID) -> SymbolID? {
        backingFieldSymbols[property]
    }

    public func setDelegateStorageSymbol(_ storage: SymbolID, for property: SymbolID) {
        delegateStorageSymbols[property] = storage
    }

    public func delegateStorageSymbol(for property: SymbolID) -> SymbolID? {
        delegateStorageSymbols[property]
    }

    public func setDelegateGetValueSymbol(_ accessor: SymbolID, for property: SymbolID) {
        delegateGetValueSymbols[property] = accessor
    }

    public func delegateGetValueSymbol(for property: SymbolID) -> SymbolID? {
        delegateGetValueSymbols[property]
    }

    public func setDelegateSetValueSymbol(_ accessor: SymbolID, for property: SymbolID) {
        delegateSetValueSymbols[property] = accessor
    }

    public func delegateSetValueSymbol(for property: SymbolID) -> SymbolID? {
        delegateSetValueSymbols[property]
    }

    public func setDelegateProvideDelegateSymbol(_ accessor: SymbolID, for property: SymbolID) {
        delegateProvideDelegateSymbols[property] = accessor
    }

    public func delegateProvideDelegateSymbol(for property: SymbolID) -> SymbolID? {
        delegateProvideDelegateSymbols[property]
    }

    public func setExtensionPropertyReceiverType(_ type: TypeID, for property: SymbolID) {
        extensionPropertyReceiverTypes[property] = type
    }

    public func extensionPropertyReceiverType(for property: SymbolID) -> TypeID? {
        extensionPropertyReceiverTypes[property]
    }

    public func setExtensionPropertyGetterAccessor(_ accessor: SymbolID, for property: SymbolID) {
        extensionPropertyGetterAccessors[property] = accessor
    }

    public func extensionPropertyGetterAccessor(for property: SymbolID) -> SymbolID? {
        extensionPropertyGetterAccessors[property]
    }

    public func setExtensionPropertySetterAccessor(_ accessor: SymbolID, for property: SymbolID) {
        extensionPropertySetterAccessors[property] = accessor
    }

    public func extensionPropertySetterAccessor(for property: SymbolID) -> SymbolID? {
        extensionPropertySetterAccessors[property]
    }

    public func setAccessorOwnerProperty(_ propertySymbol: SymbolID, for accessorSymbol: SymbolID) {
        accessorOwnerProperties[accessorSymbol] = propertySymbol
    }

    public func accessorOwnerProperty(for accessorSymbol: SymbolID) -> SymbolID? {
        accessorOwnerProperties[accessorSymbol]
    }

    public func setTypeParameterUpperBound(_ bound: TypeID, for symbol: SymbolID) {
        var bounds = typeParameterUpperBoundsMap[symbol] ?? []
        if !bounds.contains(bound) {
            bounds.append(bound)
        }
        typeParameterUpperBoundsMap[symbol] = bounds
    }

    public func setTypeParameterUpperBounds(_ bounds: [TypeID], for symbol: SymbolID) {
        var uniqueBounds: [TypeID] = []
        uniqueBounds.reserveCapacity(bounds.count)
        for bound in bounds where !uniqueBounds.contains(bound) {
            uniqueBounds.append(bound)
        }
        typeParameterUpperBoundsMap[symbol] = uniqueBounds
    }

    public func typeParameterUpperBound(for symbol: SymbolID) -> TypeID? {
        typeParameterUpperBoundsMap[symbol]?.first
    }

    public func typeParameterUpperBounds(for symbol: SymbolID) -> [TypeID] {
        typeParameterUpperBoundsMap[symbol] ?? []
    }

    public func setSourceFileID(_ fileID: FileID, for symbol: SymbolID) {
        sourceFileIDs[symbol] = fileID
    }

    public func sourceFileID(for symbol: SymbolID) -> FileID? {
        sourceFileIDs[symbol]
    }

    public func setAnnotations(_ annotations: [MetadataAnnotationRecord], for symbol: SymbolID) {
        annotationsStorage[symbol] = annotations
    }

    public func annotations(for symbol: SymbolID) -> [MetadataAnnotationRecord] {
        annotationsStorage[symbol] ?? []
    }

    public func setCompanionObjectSymbol(_ companion: SymbolID, for owner: SymbolID) {
        companionObjectSymbols[owner] = companion
    }

    public func companionObjectSymbol(for owner: SymbolID) -> SymbolID? {
        companionObjectSymbols[owner]
    }

    public func setValueClassUnderlyingType(_ type: TypeID, for symbol: SymbolID) {
        valueClassUnderlyingTypes[symbol] = type
    }

    public func valueClassUnderlyingType(for symbol: SymbolID) -> TypeID? {
        valueClassUnderlyingTypes[symbol]
    }

    public func setSealedSubclasses(_ subclasses: [SymbolID], for symbol: SymbolID) {
        sealedSubclassesStorage[symbol] = subclasses
    }

    public func setConstValueExprKind(_ kind: KIRExprKind, for symbol: SymbolID) {
        constValueExprKinds[symbol] = kind
    }

    public func constValueExprKind(for symbol: SymbolID) -> KIRExprKind? {
        constValueExprKinds[symbol]
    }

    public func sealedSubclasses(for symbol: SymbolID) -> [SymbolID]? {
        sealedSubclassesStorage[symbol]
    }

    /// Mark a property symbol as having a delegate with a `provideDelegate` operator.
    public func setHasProvideDelegate(for property: SymbolID) {
        delegateHasProvideDelegate.insert(property)
    }

    /// Returns whether the delegate type of the given property defines a `provideDelegate` operator.
    public func hasProvideDelegate(for property: SymbolID) -> Bool {
        delegateHasProvideDelegate.contains(property)
    }

    /// Link an `expect` declaration to its matching `actual` declaration.
    public func setExpectActualLink(expect: SymbolID, actual: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        expectActualLinks[expect] = actual
    }

    /// Returns the `actual` symbol linked to the given `expect` symbol, if any.
    public func actualSymbol(for expect: SymbolID) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return expectActualLinks[expect]
    }
    
    /// Validate the consistency of expect/actual links for debugging purposes
    public func validateExpectActualLinks() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        var issues: [String] = []
        
        for (expectId, actualId) in expectActualLinks {
            // Check if both symbols exist
            guard let expectSymbol = symbol(expectId) else {
                issues.append("Expect symbol \(expectId) not found in symbol table")
                continue
            }
            
            guard let actualSymbol = symbol(actualId) else {
                issues.append("Actual symbol \(actualId) not found in symbol table")
                continue
            }
            
            // Check if expect symbol has expect flag
            if !expectSymbol.flags.contains(.expectDeclaration) {
                issues.append("Symbol \(expectId) lacks expect declaration flag")
            }
            
            // Check if actual symbol has actual flag
            if !actualSymbol.flags.contains(.actualDeclaration) {
                issues.append("Symbol \(actualId) lacks actual declaration flag")
            }
            
            // Check if FQ names match (for same-package expect/actual)
            if expectSymbol.fqName == actualSymbol.fqName {
                // Same package expect/actual should have compatible kinds
                if !areKindsCompatibleForExpectActual(expect: expectSymbol.kind, actual: actualSymbol.kind) {
                    issues.append("Incompatible kinds: expect=\(expectSymbol.kind), actual=\(actualSymbol.kind)")
                }
            }
        }
        
        return issues
    }
    
    /// Check if two symbol kinds are compatible for expect/actual relationship
    private func areKindsCompatibleForExpectActual(expect: SymbolKind, actual: SymbolKind) -> Bool {
        switch (expect, actual) {
        case (.annotationClass, .annotationClass), (.annotationClass, .typeAlias):
            return true
        case (.function, .function), (.constructor, .constructor):
            return true
        case (.property, .property), (.field, .field):
            return true
        case (.class, .class), (.interface, .interface), (.object, .object):
            return true
        case (.enumClass, .enumClass):
            return true
        default:
            return expect == actual
        }
    }

    public func setContractNonNullEffect(_ effect: ContractNonNullEffect, for function: SymbolID) {
        contractNonNullEffects[function] = effect
    }

    public func contractNonNullEffect(for function: SymbolID) -> ContractNonNullEffect? {
        contractNonNullEffects[function]
    }

    public func setContractReturnsEffect(_ effect: ContractReturnsEffect, for function: SymbolID) {
        contractReturnsEffects[function] = effect
    }

    public func contractReturnsEffect(for function: SymbolID) -> ContractReturnsEffect? {
        contractReturnsEffects[function]
    }

    /// STDLIB-592: Record a `callsInPlace` effect for a function's lambda parameter.
    public func addContractCallsInPlaceEffect(_ effect: ContractCallsInPlaceEffect, for function: SymbolID) {
        contractCallsInPlaceEffects[function, default: []].append(effect)
    }

    /// STDLIB-592: Returns the `callsInPlace` effects recorded for a function, if any.
    public func contractCallsInPlaceEffects(for function: SymbolID) -> [ContractCallsInPlaceEffect] {
        contractCallsInPlaceEffects[function] ?? []
    }

    /// STDLIB-593: Record that a function has a `returnsNotNull` contract effect.
    public func setContractReturnsNotNull(for function: SymbolID) {
        contractReturnsNotNullEffects.insert(function)
    }

    /// STDLIB-593: Returns whether a function has a `returnsNotNull` contract effect.
    public func hasContractReturnsNotNull(for function: SymbolID) -> Bool {
        contractReturnsNotNullEffects.contains(function)
    }

    /// STDLIB-591: Record a `returns() implies condition` effect where the
    /// condition is a Boolean parameter at the given index.
    public func setContractConditionEffect(_ effect: ContractConditionEffect, for function: SymbolID) {
        contractConditionEffects[function] = effect
    }

    /// STDLIB-591: Returns the `returns() implies condition` effect for a function, if any.
    public func contractConditionEffect(for function: SymbolID) -> ContractConditionEffect? {
        contractConditionEffects[function]
    }

    // MARK: - Indexed queries

    /// Returns all symbol IDs of a given kind.
    public func symbols(ofKind kind: SymbolKind) -> [SymbolID] {
        byKind[kind] ?? []
    }

    /// Returns all direct child symbol IDs whose fqName parent prefix matches `parentFQName`.
    public func children(ofFQName parentFQName: [InternedString]) -> [SymbolID] {
        byParentFQName[parentFQName] ?? []
    }

    /// Returns all symbol IDs declared at the given source range.
    public func symbols(atDeclSite site: SourceRange) -> [SymbolID] {
        byDeclSite[site] ?? []
    }
}

public final class BindingTable {
    public private(set) var exprTypes: [ExprID: TypeID] = [:]
    public private(set) var identifierSymbols: [ExprID: SymbolID] = [:]
    public private(set) var callBindings: [ExprID: CallBinding] = [:]
    public private(set) var loopIterationBindings: [ExprID: LoopIterationBinding] = [:]
    public private(set) var callableTargets: [ExprID: CallableTarget] = [:]
    public private(set) var callableValueCalls: [ExprID: CallableValueCallBinding] = [:]
    public private(set) var isCheckTargetTypes: [ExprID: TypeID] = [:]
    public private(set) var castTargetTypes: [ExprID: TypeID] = [:]
    public private(set) var catchClauseBindings: [ExprID: CatchClauseBinding] = [:]
    public private(set) var captureSymbolsByExpr: [ExprID: [SymbolID]] = [:]
    public private(set) var declSymbols: [DeclID: SymbolID] = [:]
    public private(set) var superCallExprs: Set<ExprID> = []
    public private(set) var invokeOperatorCallExprs: Set<ExprID> = []
    public private(set) var collectionExprIDs: Set<ExprID> = []
    public private(set) var rangeExprIDs: Set<ExprID> = []
    public private(set) var charRangeExprIDs: Set<ExprID> = []
    public private(set) var uintRangeExprIDs: Set<ExprID> = []
    public private(set) var ulongRangeExprIDs: Set<ExprID> = []
    public private(set) var flowExprIDs: Set<ExprID> = []
    public private(set) var collectionSymbolIDs: Set<SymbolID> = []
    public private(set) var rangeSymbolIDs: Set<SymbolID> = []
    public private(set) var charRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var uintRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var ulongRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var flowSymbolIDs: Set<SymbolID> = []
    public private(set) var flowElementTypesByExpr: [ExprID: TypeID] = [:]
    public private(set) var flowElementTypesBySymbol: [SymbolID: TypeID] = [:]
    public private(set) var objectLiteralPropertySymbolIDs: Set<SymbolID> = []
    /// Maps `T::class` callable-ref expression IDs to the resolved type that
    /// `T` refers to.  Used by KIR lowering to emit the correct type token
    /// and name hint for `T::class.simpleName` / `.qualifiedName`.
    public private(set) var classRefTargetTypes: [ExprID: TypeID] = [:]
    /// Maps expression IDs to their compile-time constant values when the
    /// expression references a `const val` property.  This allows downstream
    /// passes (KIR lowering, codegen) to fold constant references without
    /// re-querying the symbol table.
    public private(set) var constExprValues: [ExprID: KIRExprKind] = [:]
    /// Tracks lambda expressions that undergo SAM (functional interface) conversion.
    public private(set) var samConversionExprs: Set<ExprID> = []
    /// Maps SAM-converted lambda expressions to their underlying function type,
    /// so KIR lowering can generate the correct callable signature.
    public private(set) var samUnderlyingFunctionTypes: [ExprID: TypeID] = [:]
    /// Tracks call expressions that are builder DSL calls (buildString/buildList/buildMap).
    public private(set) var builderDSLExprIDs: Set<ExprID> = []
    /// Maps builder DSL call expression IDs to their builder kind.
    public private(set) var builderDSLKinds: [ExprID: BuilderDSLKind] = [:]
    /// Tracks call expressions that are scope function calls (STDLIB-004).
    public private(set) var scopeFunctionExprIDs: Set<ExprID> = []
    /// Maps scope function call expression IDs to their kind.
    public private(set) var scopeFunctionKinds: [ExprID: ScopeFunctionKind] = [:]
    /// Tracks takeIf / takeUnless extension calls (STDLIB-160).
    public private(set) var takeIfTakeUnlessExprIDs: Set<ExprID> = []
    /// Maps takeIf/takeUnless call expression IDs to their kind.
    public private(set) var takeIfTakeUnlessKinds: [ExprID: TakeIfTakeUnlessKind] = [:]
    /// Tracks lambda literals that need the collection HOF closure parameter ABI.
    public private(set) var collectionHOFLambdaExprIDs: Set<ExprID> = []
    /// Tracks stdlib calls that require dedicated lowering.
    public private(set) var stdlibSpecialCallExprIDs: Set<ExprID> = []
    /// Maps stdlib special call expressions to their lowering kind.
    public private(set) var stdlibSpecialCallKinds: [ExprID: StdlibSpecialCallKind] = [:]
    /// Maps nameRef expression IDs to their member name when they were resolved
    /// as implicit receiver member accesses (STDLIB-004).
    public private(set) var implicitReceiverMemberNames: [ExprID: InternedString] = [:]
    /// Maps callable reference expression IDs to their kind (function vs property)
    /// so that KIR lowering can emit KFunction / KProperty type identity (REFL-003).
    public private(set) var callableRefKinds: [ExprID: CallableRefKind] = [:]
    /// Tracks callable reference expressions that are unbound type references
    /// (e.g. `Type::member`).  The receiver is not captured; instead it
    /// becomes a parameter of the resulting function type (REFL-003).
    public private(set) var unboundCallableRefs: Set<ExprID> = []

    public init() {}

    public func bindExprType(_ expr: ExprID, type: TypeID) {
        exprTypes[expr] = type
    }

    public func bindIdentifier(_ expr: ExprID, symbol: SymbolID) {
        identifierSymbols[expr] = symbol
    }

    public func bindCall(_ expr: ExprID, binding: CallBinding) {
        callBindings[expr] = binding
    }

    public func bindLoopIteration(_ expr: ExprID, binding: LoopIterationBinding) {
        loopIterationBindings[expr] = binding
    }

    public func bindCallableTarget(_ expr: ExprID, target: CallableTarget) {
        callableTargets[expr] = target
    }

    public func bindCallableValueCall(_ expr: ExprID, binding: CallableValueCallBinding) {
        callableValueCalls[expr] = binding
    }

    public func bindIsCheckTargetType(_ expr: ExprID, type: TypeID) {
        isCheckTargetTypes[expr] = type
    }

    public func bindCastTargetType(_ expr: ExprID, type: TypeID) {
        castTargetTypes[expr] = type
    }

    public func bindCatchClause(_ catchBodyExpr: ExprID, binding: CatchClauseBinding) {
        catchClauseBindings[catchBodyExpr] = binding
    }

    public func bindCaptureSymbols(_ expr: ExprID, symbols: [SymbolID]) {
        let unique = Array(Set(symbols)).sorted(by: { $0.rawValue < $1.rawValue })
        captureSymbolsByExpr[expr] = unique
    }

    public func bindDecl(_ decl: DeclID, symbol: SymbolID) {
        declSymbols[decl] = symbol
    }

    public func markSuperCall(_ expr: ExprID) {
        superCallExprs.insert(expr)
    }

    public func markInvokeOperatorCall(_ expr: ExprID) {
        invokeOperatorCallExprs.insert(expr)
    }

    public func markCollectionExpr(_ expr: ExprID) {
        collectionExprIDs.insert(expr)
    }

    public func isCollectionExpr(_ expr: ExprID) -> Bool {
        collectionExprIDs.contains(expr)
    }

    public func markRangeExpr(_ expr: ExprID) {
        rangeExprIDs.insert(expr)
    }

    public func isRangeExpr(_ expr: ExprID) -> Bool {
        rangeExprIDs.contains(expr)
    }

    public func markCharRangeExpr(_ expr: ExprID) {
        charRangeExprIDs.insert(expr)
    }

    public func isCharRangeExpr(_ expr: ExprID) -> Bool {
        charRangeExprIDs.contains(expr)
    }

    public func markUIntRangeExpr(_ expr: ExprID) {
        uintRangeExprIDs.insert(expr)
    }

    public func isUIntRangeExpr(_ expr: ExprID) -> Bool {
        uintRangeExprIDs.contains(expr)
    }

    public func markULongRangeExpr(_ expr: ExprID) {
        ulongRangeExprIDs.insert(expr)
    }

    public func isULongRangeExpr(_ expr: ExprID) -> Bool {
        ulongRangeExprIDs.contains(expr)
    }

    public func markFlowExpr(_ expr: ExprID) {
        flowExprIDs.insert(expr)
    }

    public func isFlowExpr(_ expr: ExprID) -> Bool {
        flowExprIDs.contains(expr)
    }

    public func bindFlowElementType(_ type: TypeID, forExpr expr: ExprID) {
        flowExprIDs.insert(expr)
        flowElementTypesByExpr[expr] = type
    }

    public func flowElementType(forExpr expr: ExprID) -> TypeID? {
        flowElementTypesByExpr[expr]
    }

    public func markObjectLiteralPropertySymbol(_ symbol: SymbolID) {
        objectLiteralPropertySymbolIDs.insert(symbol)
    }

    public func isObjectLiteralPropertySymbol(_ symbol: SymbolID) -> Bool {
        objectLiteralPropertySymbolIDs.contains(symbol)
    }

    public func markCollectionSymbol(_ symbol: SymbolID) {
        collectionSymbolIDs.insert(symbol)
    }

    public func isCollectionSymbol(_ symbol: SymbolID) -> Bool {
        collectionSymbolIDs.contains(symbol)
    }

    public func markRangeSymbol(_ symbol: SymbolID) {
        rangeSymbolIDs.insert(symbol)
    }

    public func isRangeSymbol(_ symbol: SymbolID) -> Bool {
        rangeSymbolIDs.contains(symbol)
    }

    public func markCharRangeSymbol(_ symbol: SymbolID) {
        charRangeSymbolIDs.insert(symbol)
    }

    public func isCharRangeSymbol(_ symbol: SymbolID) -> Bool {
        charRangeSymbolIDs.contains(symbol)
    }

    public func markUIntRangeSymbol(_ symbol: SymbolID) {
        uintRangeSymbolIDs.insert(symbol)
    }

    public func isUIntRangeSymbol(_ symbol: SymbolID) -> Bool {
        uintRangeSymbolIDs.contains(symbol)
    }

    public func markULongRangeSymbol(_ symbol: SymbolID) {
        ulongRangeSymbolIDs.insert(symbol)
    }

    public func isULongRangeSymbol(_ symbol: SymbolID) -> Bool {
        ulongRangeSymbolIDs.contains(symbol)
    }

    public func markFlowSymbol(_ symbol: SymbolID) {
        flowSymbolIDs.insert(symbol)
    }

    public func unmarkFlowSymbol(_ symbol: SymbolID) {
        flowSymbolIDs.remove(symbol)
        flowElementTypesBySymbol.removeValue(forKey: symbol)
    }

    public func isFlowSymbol(_ symbol: SymbolID) -> Bool {
        flowSymbolIDs.contains(symbol)
    }

    public func bindFlowElementType(_ type: TypeID, forSymbol symbol: SymbolID) {
        flowSymbolIDs.insert(symbol)
        flowElementTypesBySymbol[symbol] = type
    }

    public func flowElementType(forSymbol symbol: SymbolID) -> TypeID? {
        flowElementTypesBySymbol[symbol]
    }

    public func bindClassRefTargetType(_ expr: ExprID, type: TypeID) {
        classRefTargetTypes[expr] = type
    }

    public func classRefTargetType(for expr: ExprID) -> TypeID? {
        classRefTargetTypes[expr]
    }

    public func exprType(for expr: ExprID) -> TypeID? {
        exprTypes[expr]
    }

    public func identifierSymbol(for expr: ExprID) -> SymbolID? {
        identifierSymbols[expr]
    }

    public func callBinding(for expr: ExprID) -> CallBinding? {
        callBindings[expr]
    }

    public func loopIterationBinding(for expr: ExprID) -> LoopIterationBinding? {
        loopIterationBindings[expr]
    }

    public func callableTarget(for expr: ExprID) -> CallableTarget? {
        callableTargets[expr]
    }

    public func callableValueCallBinding(for expr: ExprID) -> CallableValueCallBinding? {
        callableValueCalls[expr]
    }

    public func isCheckTargetType(for expr: ExprID) -> TypeID? {
        isCheckTargetTypes[expr]
    }

    public func castTargetType(for expr: ExprID) -> TypeID? {
        castTargetTypes[expr]
    }

    public func catchClauseBinding(for catchBodyExpr: ExprID) -> CatchClauseBinding? {
        catchClauseBindings[catchBodyExpr]
    }

    public func captureSymbols(for expr: ExprID) -> [SymbolID] {
        captureSymbolsByExpr[expr] ?? []
    }

    public func declSymbol(for decl: DeclID) -> SymbolID? {
        declSymbols[decl]
    }

    public func isSuperCallExpr(_ expr: ExprID) -> Bool {
        superCallExprs.contains(expr)
    }

    public func isInvokeOperatorCall(_ expr: ExprID) -> Bool {
        invokeOperatorCallExprs.contains(expr)
    }

    /// Record the compile-time constant value for an expression that
    /// references a `const val` property.  Called during type-check when
    /// a name-ref resolves to a symbol carrying `.constValue`.
    public func bindConstExprValue(_ expr: ExprID, value: KIRExprKind) {
        constExprValues[expr] = value
    }

    /// Retrieve the compile-time constant value for an expression, if any.
    public func constExprValue(for expr: ExprID) -> KIRExprKind? {
        constExprValues[expr]
    }

    /// Mark a lambda expression as undergoing SAM (functional interface) conversion.
    public func markSamConversion(_ expr: ExprID) {
        samConversionExprs.insert(expr)
    }

    /// Whether the given expression is a SAM-converted lambda.
    public func isSamConversion(_ expr: ExprID) -> Bool {
        samConversionExprs.contains(expr)
    }

    /// Store the underlying function type for a SAM-converted lambda, so that
    /// KIR lowering can generate the callable with the correct signature.
    public func bindSamUnderlyingFunctionType(_ expr: ExprID, type: TypeID) {
        samUnderlyingFunctionTypes[expr] = type
    }

    /// Retrieve the underlying function type for a SAM-converted lambda.
    public func samUnderlyingFunctionType(for expr: ExprID) -> TypeID? {
        samUnderlyingFunctionTypes[expr]
    }

    /// Mark a call expression as a builder DSL call (buildString/buildList/buildMap).
    public func markBuilderDSLExpr(_ expr: ExprID, kind: BuilderDSLKind) {
        builderDSLExprIDs.insert(expr)
        builderDSLKinds[expr] = kind
    }

    /// Whether the given expression is a builder DSL call.
    public func isBuilderDSLExpr(_ expr: ExprID) -> Bool {
        builderDSLExprIDs.contains(expr)
    }

    /// Retrieve the builder DSL kind for a builder call expression.
    public func builderDSLKind(for expr: ExprID) -> BuilderDSLKind? {
        builderDSLKinds[expr]
    }

    /// Mark a call expression as a scope function call (STDLIB-004).
    public func markScopeFunctionExpr(_ expr: ExprID, kind: ScopeFunctionKind) {
        scopeFunctionExprIDs.insert(expr)
        scopeFunctionKinds[expr] = kind
    }

    /// Whether the given expression is a scope function call.
    public func isScopeFunctionExpr(_ expr: ExprID) -> Bool {
        scopeFunctionExprIDs.contains(expr)
    }

    /// Retrieve the scope function kind for a scope function call expression.
    public func scopeFunctionKind(for expr: ExprID) -> ScopeFunctionKind? {
        scopeFunctionKinds[expr]
    }

    /// Mark a call expression as a takeIf / takeUnless extension call (STDLIB-160).
    public func markTakeIfTakeUnlessExpr(_ expr: ExprID, kind: TakeIfTakeUnlessKind) {
        takeIfTakeUnlessExprIDs.insert(expr)
        takeIfTakeUnlessKinds[expr] = kind
    }

    /// Whether the given expression is a takeIf / takeUnless call.
    public func isTakeIfTakeUnlessExpr(_ expr: ExprID) -> Bool {
        takeIfTakeUnlessExprIDs.contains(expr)
    }

    /// Retrieve the takeIf/takeUnless kind for a marked call expression.
    public func takeIfTakeUnlessKind(for expr: ExprID) -> TakeIfTakeUnlessKind? {
        takeIfTakeUnlessKinds[expr]
    }

    /// Mark a lambda literal as requiring collection HOF closure ABI lowering.
    public func markCollectionHOFLambdaExpr(_ expr: ExprID) {
        collectionHOFLambdaExprIDs.insert(expr)
    }

    /// Whether the lambda literal requires collection HOF closure ABI lowering.
    public func isCollectionHOFLambdaExpr(_ expr: ExprID) -> Bool {
        collectionHOFLambdaExprIDs.contains(expr)
    }

    /// Mark a call expression as a stdlib special call requiring custom lowering.
    public func markStdlibSpecialCallExpr(_ expr: ExprID, kind: StdlibSpecialCallKind) {
        stdlibSpecialCallExprIDs.insert(expr)
        stdlibSpecialCallKinds[expr] = kind
    }

    /// Whether the given expression is a stdlib special call.
    public func isStdlibSpecialCallExpr(_ expr: ExprID) -> Bool {
        stdlibSpecialCallExprIDs.contains(expr)
    }

    /// Retrieve the stdlib special call kind for a marked call expression.
    public func stdlibSpecialCallKind(for expr: ExprID) -> StdlibSpecialCallKind? {
        stdlibSpecialCallKinds[expr]
    }

    /// Mark a nameRef expression as an implicit receiver member access (STDLIB-004).
    public func markImplicitReceiverMember(_ expr: ExprID, name: InternedString) {
        implicitReceiverMemberNames[expr] = name
    }

    /// Bind a callable reference expression to its kind (REFL-003).
    public func bindCallableRefKind(_ expr: ExprID, kind: CallableRefKind) {
        callableRefKinds[expr] = kind
    }

    /// Query the callable reference kind for an expression (REFL-003).
    public func callableRefKind(for expr: ExprID) -> CallableRefKind? {
        callableRefKinds[expr]
    }

    /// Mark a callable reference as an unbound type reference (REFL-003).
    public func markUnboundCallableRef(_ expr: ExprID) {
        unboundCallableRefs.insert(expr)
    }

    /// Query whether a callable reference is an unbound type reference (REFL-003).
    public func isUnboundCallableRef(_ expr: ExprID) -> Bool {
        unboundCallableRefs.contains(expr)
    }
}

public final class SemaModule {
    public let symbols: SymbolTable
    public let types: TypeSystem
    public let bindings: BindingTable
    public let diagnostics: DiagnosticEngine
    public var importedInlineFunctions: [SymbolID: KIRFunction]

    public init(
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        importedInlineFunctions: [SymbolID: KIRFunction] = [:]
    ) {
        self.symbols = symbols
        self.types = types
        self.bindings = bindings
        self.diagnostics = diagnostics
        self.importedInlineFunctions = importedInlineFunctions
    }
}
