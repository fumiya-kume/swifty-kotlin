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
    /// Per-instruction source locations, parallel to ``instructions``.
    /// `nil` entries mean "same as function-level location".
    var instructionLocations: [SourceRange?]
    /// The current source range to associate with newly appended instructions.
    /// Set this before appending instructions to propagate source locations.
    var currentSourceRange: SourceRange?

    init(_ instructions: [KIRInstruction] = []) {
        self.instructions = instructions
        instructionLocations = Array(repeating: nil, count: instructions.count)
        currentSourceRange = nil
    }

    init() {
        instructions = []
        instructionLocations = []
        currentSourceRange = nil
    }

    init(arrayLiteral elements: KIRInstruction...) {
        instructions = elements
        instructionLocations = Array(repeating: nil, count: elements.count)
        currentSourceRange = nil
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

    mutating func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with newElements: C) where KIRInstruction == C.Element {
        instructions.replaceSubrange(subrange, with: newElements)
        // Keep instructionLocations in sync with the same structural edit.
        if instructionLocations.count < subrange.upperBound {
            instructionLocations.append(
                contentsOf: repeatElement(nil, count: subrange.upperBound - instructionLocations.count)
            )
        }
        let newLocations = Array(repeating: currentSourceRange, count: newElements.count)
        instructionLocations.replaceSubrange(subrange, with: newLocations)
        // Final safety sync.
        if instructionLocations.count < instructions.count {
            instructionLocations.append(
                contentsOf: repeatElement(nil, count: instructions.count - instructionLocations.count)
            )
        } else if instructionLocations.count > instructions.count {
            instructionLocations.removeLast(instructionLocations.count - instructions.count)
        }
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
        isTailrec: Bool = false,
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
            isTailrec: isTailrec,
            sourceRange: sourceRange,
            instructionLocations: body.instructionLocations
        )
    }
}
