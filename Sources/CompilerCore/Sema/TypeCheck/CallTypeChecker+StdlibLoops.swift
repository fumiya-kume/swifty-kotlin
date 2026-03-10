import Foundation

extension CallTypeChecker {
    func shouldUseRepeatSpecialHandling(
        calleeName: InternedString,
        locals: LocalBindings
    ) -> Bool {
        locals[calleeName] == nil
    }
}
