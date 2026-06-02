/// Pre-interned Kotlin builtin type name strings.
/// Use this instead of comparing `interner.resolve(x) == "Int"` etc.
/// Comparison becomes `x == builtinNames.int` which is Int32 == Int32.
struct BuiltinTypeNames {
    let int: InternedString
    let long: InternedString
    let float: InternedString
    let double: InternedString
    let boolean: InternedString
    let char: InternedString
    let string: InternedString
    let uint: InternedString
    let ulong: InternedString
    let ubyte: InternedString
    let ushort: InternedString
    let any: InternedString
    let number: InternedString
    let unit: InternedString
    let nothing: InternedString
    let annotation: InternedString
    let null: InternedString

    init(interner: StringInterner) {
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
        self.number = interner.intern("Number")
        self.unit = interner.intern("Unit")
        self.nothing = interner.intern("Nothing")
        self.annotation = interner.intern("Annotation")
        self.null = interner.intern("null")
    }

    /// Resolve an InternedString to a PrimitiveType, or nil if not a primitive.
    func primitiveType(for name: InternedString) -> PrimitiveType? {
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
    func resolveBuiltinType(
        _ name: InternedString,
        nullability: Nullability = .nonNull,
        types: TypeSystem
    ) -> TypeID? {
        if let prim = primitiveType(for: name) {
            return types.withNullability(nullability, for: types.make(.primitive(prim, .nonNull)))
        }
        if name == any || name == number {
            return nullability == .nullable ? types.nullableAnyType : types.anyType
        }
        if name == unit { return types.unitType }
        if name == nothing { return nullability == .nullable ? types.nullableNothingType : types.nothingType }
        if name == annotation {
            if let symbol = types.annotationInterfaceSymbol {
                return types.make(.classType(ClassType(classSymbol: symbol, nullability: nullability)))
            }
        }
        return nil
    }
}
