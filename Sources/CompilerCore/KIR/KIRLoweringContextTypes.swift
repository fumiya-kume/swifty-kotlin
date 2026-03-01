import Foundation

struct KIRLoweringSharedContext {
    let ast: ASTModule
    let sema: SemaModule
    let arena: KIRArena
    let interner: StringInterner
    let propertyConstantInitializers: [SymbolID: KIRExprKind]
}

struct KIRLoweringEmitContext: RandomAccessCollection, MutableCollection, RangeReplaceableCollection, ExpressibleByArrayLiteral {
    typealias Element = KIRInstruction
    typealias Index = Array<KIRInstruction>.Index

    var instructions: [KIRInstruction]

    init(_ instructions: [KIRInstruction] = []) {
        self.instructions = instructions
    }

    init() {
        self.instructions = []
    }

    init(arrayLiteral elements: KIRInstruction...) {
        self.instructions = elements
    }

    var startIndex: Index {
        instructions.startIndex
    }

    var endIndex: Index {
        instructions.endIndex
    }

    func index(after i: Index) -> Index {
        instructions.index(after: i)
    }

    func index(before i: Index) -> Index {
        instructions.index(before: i)
    }

    subscript(position: Index) -> KIRInstruction {
        get { instructions[position] }
        set { instructions[position] = newValue }
    }

    mutating func replaceSubrange<C>(_ subrange: Range<Index>, with newElements: C) where C: Collection, KIRInstruction == C.Element {
        instructions.replaceSubrange(subrange, with: newElements)
    }
}

extension KIRFunction {
    init(
        symbol: SymbolID,
        name: InternedString,
        params: [KIRParameter],
        returnType: TypeID,
        body: KIRLoweringEmitContext,
        isSuspend: Bool,
        isInline: Bool,
        sourceRange: SourceRange? = nil
    ) {
        self.init(
            symbol: symbol,
            name: name,
            params: params,
            returnType: returnType,
            body: body.instructions,
            isSuspend: isSuspend,
            isInline: isInline,
            sourceRange: sourceRange
        )
    }
}
