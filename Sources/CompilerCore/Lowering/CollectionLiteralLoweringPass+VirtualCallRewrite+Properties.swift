import Foundation

extension CollectionLiteralLoweringPass {
    // MARK: - Collection property operations (size, contains, isEmpty)

    func rewriteCollectionPropertyVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: Set<Int32>,
        setExprIDs: Set<Int32>,
        mapExprIDs: Set<Int32>,
        arrayExprIDs: Set<Int32> = [],
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        if callee == lookup.sizeName || callee == lookup.countName, arguments.isEmpty {
            if listExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if setExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if mapExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if arrayExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArraySizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.containsName, arguments.count == 1 {
            if listExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListContainsName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if setExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetContainsName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.isEmptyName, arguments.isEmpty {
            if listExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if setExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if mapExprIDs.contains(receiver.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        return false
    }
}
