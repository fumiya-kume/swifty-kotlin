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
}

public struct SemanticSymbol: Sendable {
    public let id: SymbolID
    public let kind: SymbolKind
    public let name: InternedString
    public let fqName: [InternedString]
    public let declSite: SourceRange?
    public let visibility: Visibility
    public let flags: SymbolFlags
}

public struct FunctionSignature: Hashable, Sendable {
    public let receiverType: TypeID?
    public let parameterTypes: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
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

// swiftlint:disable:next type_body_length
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
    /// CLASS-008: Interfaces delegated by a class via `: Interface by expr`.
    /// Key = class symbol, Value = set of interface symbols that class delegates to.
    private var delegatedInterfacesByClass: [SymbolID: Set<SymbolID>] = [:]

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

    public func lookup(fqName: [InternedString]) -> SymbolID? {
        byFQName[fqName]?.first
    }

    public func lookupAll(fqName: [InternedString]) -> [SymbolID] {
        byFQName[fqName] ?? []
    }

    public func lookupByShortName(_ name: InternedString) -> [SymbolID] {
        byShortName[name] ?? []
    }

    public func define(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange?,
        visibility: Visibility,
        flags: SymbolFlags = []
    ) -> SymbolID {
        if let existing = byFQName[fqName], !existing.isEmpty {
            let existingSymbols = existing.compactMap { symbol($0) }
            let existingKinds = existingSymbols.map(\.kind)

            let shouldCoexist = canCoexistAsOverload(kind: kind, existingKinds: existingKinds)
                || canCoexistAsExpectActual(kind: kind, flags: flags, existingSymbols: existingSymbols)
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
        if kind == .package {
            return true
        }
        let existingNonPackageKinds = existingKinds.filter { $0 != .package }
        if existingNonPackageKinds.isEmpty {
            return true
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
        // For Kotlin MPP, allow one `expect` + one `actual` symbol with the same FQ name.
        // This is required for non-overloadable kinds like properties and classes.
        let isNewExpect = flags.contains(.expectDeclaration)
        let isNewActual = flags.contains(.actualDeclaration)
        guard isNewExpect || isNewActual, !(isNewExpect && isNewActual) else {
            return false
        }

        let oppositeFlag: SymbolFlags = isNewExpect ? .actualDeclaration : .expectDeclaration
        let sameFlag: SymbolFlags = isNewExpect ? .expectDeclaration : .actualDeclaration

        let sameKindExisting = existingSymbols.filter { $0.kind == kind }
        let hasOpposite = sameKindExisting.contains { $0.flags.contains(oppositeFlag) }
        let hasSame = sameKindExisting.contains { $0.flags.contains(sameFlag) }

        // Only permit coexistence when we're pairing an `expect` with an `actual`.
        // If a non-MPP symbol already exists at this name+kind, treat it as a conflict.
        let hasNonMPP = sameKindExisting.contains { sym in
            !sym.flags.contains(.expectDeclaration) && !sym.flags.contains(.actualDeclaration)
        }

        return hasOpposite && !hasSame && !hasNonMPP
    }

    private func isOverloadable(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
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

    // swiftlint:disable large_tuple line_length
    /// CLASS-008: Synthetic forwarding method symbols created for class delegation.
    /// Maps forwarding method symbol -> (interfaceSymbol, interfaceMethodSymbol, fieldSymbol).
    private var classDelegationForwardingMethodInfo: [SymbolID: (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)] = [:]
    // swiftlint:enable large_tuple line_length

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

    // swiftlint:disable large_tuple line_length
    /// CLASS-008: Get the info needed to emit the forwarding body for a synthetic method.
    public func classDelegationForwardingMethodInfo(for forwardingSymbol: SymbolID) -> (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)? {
        classDelegationForwardingMethodInfo[forwardingSymbol]
    }

    // swiftlint:enable large_tuple line_length

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
        typeAliasUnderlyingTypes[symbol] = type
    }

    public func typeAliasUnderlyingType(for symbol: SymbolID) -> TypeID? {
        typeAliasUnderlyingTypes[symbol]
    }

    public func setTypeAliasTypeParameters(_ params: [SymbolID], for symbol: SymbolID) {
        typeAliasTypeParameters[symbol] = params
    }

    public func typeAliasTypeParameters(for symbol: SymbolID) -> [SymbolID] {
        typeAliasTypeParameters[symbol] ?? []
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
        expectActualLinks[expect] = actual
    }

    /// Returns the `actual` symbol linked to the given `expect` symbol, if any.
    public func actualSymbol(for expect: SymbolID) -> SymbolID? {
        expectActualLinks[expect]
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
    public private(set) var flowExprIDs: Set<ExprID> = []
    public private(set) var collectionSymbolIDs: Set<SymbolID> = []
    public private(set) var flowSymbolIDs: Set<SymbolID> = []
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
    /// Maps nameRef expression IDs to their member name when they were resolved
    /// as implicit receiver member accesses (STDLIB-004).
    public private(set) var implicitReceiverMemberNames: [ExprID: InternedString] = [:]

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

    public func markFlowExpr(_ expr: ExprID) {
        flowExprIDs.insert(expr)
    }

    public func isFlowExpr(_ expr: ExprID) -> Bool {
        flowExprIDs.contains(expr)
    }

    public func markCollectionSymbol(_ symbol: SymbolID) {
        collectionSymbolIDs.insert(symbol)
    }

    public func isCollectionSymbol(_ symbol: SymbolID) -> Bool {
        collectionSymbolIDs.contains(symbol)
    }

    public func markFlowSymbol(_ symbol: SymbolID) {
        flowSymbolIDs.insert(symbol)
    }

    public func isFlowSymbol(_ symbol: SymbolID) -> Bool {
        flowSymbolIDs.contains(symbol)
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

    /// Mark a nameRef expression as an implicit receiver member access (STDLIB-004).
    public func markImplicitReceiverMember(_ expr: ExprID, name: InternedString) {
        implicitReceiverMemberNames[expr] = name
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
