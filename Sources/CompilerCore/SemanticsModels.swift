public struct SymbolID: Hashable {
    public let rawValue: Int32

    public static let invalid = SymbolID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum SymbolKind: Equatable {
    case package
    case `class`
    case `interface`
    case object
    case enumClass
    case annotationClass
    case typeAlias
    case function
    case constructor
    case property
    case field
    case typeParameter
    case valueParameter
    case local
    case label
}

public struct SymbolFlags: OptionSet {
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
}

public struct SemanticSymbol {
    public let id: SymbolID
    public let kind: SymbolKind
    public let name: InternedString
    public let fqName: [InternedString]
    public let declSite: SourceRange?
    public let visibility: Visibility
    public let flags: SymbolFlags
}

public struct FunctionSignature {
    public let receiverType: TypeID?
    public let parameterTypes: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let valueParameterSymbols: [SymbolID]
    public let valueParameterHasDefaultValues: [Bool]
    public let valueParameterIsVararg: [Bool]
    public let typeParameterSymbols: [SymbolID]
    public let reifiedTypeParameterIndices: Set<Int>

    public init(
        receiverType: TypeID? = nil,
        parameterTypes: [TypeID],
        returnType: TypeID,
        isSuspend: Bool = false,
        valueParameterSymbols: [SymbolID] = [],
        valueParameterHasDefaultValues: [Bool] = [],
        valueParameterIsVararg: [Bool] = [],
        typeParameterSymbols: [SymbolID] = [],
        reifiedTypeParameterIndices: Set<Int> = []
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
    }
}

public struct NominalLayout: Equatable {
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

public struct NominalLayoutHint: Equatable {
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
}

public final class FileScope: BaseScope {}
public final class PackageScope: BaseScope {}
public final class ImportScope: BaseScope {}
public final class ClassMemberScope: BaseScope {}
public final class FunctionScope: BaseScope {}
public final class BlockScope: BaseScope {}

public final class SymbolTable {
    private var symbolsStorage: [SemanticSymbol] = []
    private var byFQName: [[InternedString]: [SymbolID]] = [:]
    private var functionSignatures: [SymbolID: FunctionSignature] = [:]
    private var propertyTypes: [SymbolID: TypeID] = [:]
    private var directSupertypes: [SymbolID: [SymbolID]] = [:]
    private var nominalLayouts: [SymbolID: NominalLayout] = [:]
    private var nominalLayoutHints: [SymbolID: NominalLayoutHint] = [:]
    private var externalLinkNames: [SymbolID: String] = [:]
    private var typeAliasUnderlyingTypes: [SymbolID: TypeID] = [:]

    public init() {}

    public var count: Int {
        symbolsStorage.count
    }

    public func allSymbols() -> [SemanticSymbol] {
        symbolsStorage
    }

    public func symbol(_ id: SymbolID) -> SemanticSymbol? {
        let index = Int(id.rawValue)
        guard index >= 0 && index < symbolsStorage.count else {
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

    public func define(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange?,
        visibility: Visibility,
        flags: SymbolFlags = []
    ) -> SymbolID {
        if let existing = byFQName[fqName], !existing.isEmpty {
            let existingKinds = existing.compactMap { symbol($0)?.kind }
            if canCoexistAsOverload(kind: kind, existingKinds: existingKinds) {
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
        return id
    }

    private func canCoexistAsOverload(kind: SymbolKind, existingKinds: [SymbolKind]) -> Bool {
        guard isOverloadable(kind) else {
            return false
        }
        return existingKinds.allSatisfy { isOverloadable($0) }
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

    public func directSubtypes(of symbol: SymbolID) -> [SymbolID] {
        var result: [SymbolID] = []
        for (candidate, supertypes) in directSupertypes {
            if supertypes.contains(symbol) {
                result.append(candidate)
            }
        }
        return result.sorted(by: { $0.rawValue < $1.rawValue })
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
        typeAliasUnderlyingTypes[symbol] = type
    }

    public func typeAliasUnderlyingType(for symbol: SymbolID) -> TypeID? {
        typeAliasUnderlyingTypes[symbol]
    }
}

public struct CallBinding {
    public let chosenCallee: SymbolID
    public let substitutedTypeArguments: [TypeID]
    public let parameterMapping: [Int: Int]

    public init(chosenCallee: SymbolID, substitutedTypeArguments: [TypeID], parameterMapping: [Int: Int]) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
    }
}

public final class BindingTable {
    public private(set) var exprTypes: [ExprID: TypeID] = [:]
    public private(set) var identifierSymbols: [ExprID: SymbolID] = [:]
    public private(set) var callBindings: [ExprID: CallBinding] = [:]
    public private(set) var declSymbols: [DeclID: SymbolID] = [:]

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

    public func bindDecl(_ decl: DeclID, symbol: SymbolID) {
        declSymbols[decl] = symbol
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
