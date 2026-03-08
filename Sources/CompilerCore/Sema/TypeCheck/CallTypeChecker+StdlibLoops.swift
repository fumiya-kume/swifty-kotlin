import Foundation

extension CallTypeChecker {
    func shouldUseRepeatSpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        _ = ctx
        return locals[calleeName] == nil
    }
}
