import Foundation

// Internal visibility is required for cross-file extension decomposition.
struct TypeInferenceContext {
    let ast: ASTModule
    let sema: SemaModule
    let semaCtx: SemaModule
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    var scope: Scope
    var implicitReceiverType: TypeID?
    var loopDepth: Int
    var flowState: DataFlowState
    let currentFileID: FileID
    var enclosingClassSymbol: SymbolID?
    let visibilityChecker: VisibilityChecker

    func with(scope newScope: Scope) -> TypeInferenceContext {
        var copy = self; copy.scope = newScope; return copy
    }

    func with(implicitReceiverType newType: TypeID?) -> TypeInferenceContext {
        var copy = self; copy.implicitReceiverType = newType; return copy
    }

    func with(loopDepth newDepth: Int) -> TypeInferenceContext {
        var copy = self; copy.loopDepth = newDepth; return copy
    }

    func with(flowState newState: DataFlowState) -> TypeInferenceContext {
        var copy = self; copy.flowState = newState; return copy
    }

    func with(enclosingClassSymbol newSymbol: SymbolID?) -> TypeInferenceContext {
        var copy = self; copy.enclosingClassSymbol = newSymbol; return copy
    }

    func filterByVisibility(_ candidates: [SymbolID]) -> (visible: [SymbolID], invisible: [SemanticSymbol]) {
        var visible: [SymbolID] = []
        var invisible: [SemanticSymbol] = []
        for candidate in candidates {
            guard let symbol = sema.symbols.symbol(candidate) else { continue }
            if visibilityChecker.isAccessible(symbol, fromFile: currentFileID, enclosingClass: enclosingClassSymbol) {
                visible.append(candidate)
            } else {
                invisible.append(symbol)
            }
        }
        return (visible, invisible)
    }
}
