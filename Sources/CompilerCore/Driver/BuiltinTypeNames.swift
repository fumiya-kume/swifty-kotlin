/// Pre-interned Kotlin builtin type name strings.
/// Use this instead of comparing `interner.resolve(x) == "Int"` etc.
/// Comparison becomes `x == builtinNames.int` which is Int32 == Int32.
public struct BuiltinTypeNames {
    public let int: InternedString
    public let long: InternedString
    public let float: InternedString
    public let double: InternedString
    public let boolean: InternedString
    public let char: InternedString
    public let string: InternedString
    public let uint: InternedString
    public let ulong: InternedString
    public let ubyte: InternedString
    public let ushort: InternedString
    public let any: InternedString
    public let unit: InternedString
    public let nothing: InternedString
    public let null: InternedString
    public let intArray: InternedString

    public init(interner: StringInterner) {
        self.int = interner.intern("Int")
        self.long = interner.intern("Long")
        self.float = interner.intern("Float")
        self.double = interner.intern("Double")
        self.boolean = interner.intern("Boolean")
        self.char = interner.intern("Char")
        self.string = interner.intern("String")
        self.uint = interner.intern("UInt")
        self.ulong = interner.intern("ULong")
        self.ubyte = interner.intern("UByte")
        self.ushort = interner.intern("UShort")
        self.any = interner.intern("Any")
        self.unit = interner.intern("Unit")
        self.nothing = interner.intern("Nothing")
        self.null = interner.intern("null")
        self.intArray = interner.intern("IntArray")
    }

    /// Resolve an InternedString to a PrimitiveType, or nil if not a primitive.
    public func primitiveType(for name: InternedString) -> PrimitiveType? {
        if name == int { return .int }
        if name == long { return .long }
        if name == float { return .float }
        if name == double { return .double }
        if name == boolean { return .boolean }
        if name == char { return .char }
        if name == string { return .string }
        if name == uint { return .uint }
        if name == ulong { return .ulong }
        if name == ubyte { return .ubyte }
        if name == ushort { return .ushort }
        return nil
    }

    /// Resolve an InternedString to a builtin TypeID (including Any/Unit/Nothing), or nil.
    public func resolveBuiltinType(
        _ name: InternedString,
        nullability: Nullability = .nonNull,
        types: TypeSystem
    ) -> TypeID? {
        if let prim = primitiveType(for: name) {
            return types.withNullability(nullability, for: types.make(.primitive(prim, .nonNull)))
        }
        if name == any { return nullability == .nullable ? types.nullableAnyType : types.anyType }
        if name == unit { return types.unitType }
        if name == nothing { return nullability == .nullable ? types.nullableNothingType : types.nothingType }
        return nil
    }
}
