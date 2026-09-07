extension CollectionLiteralLoweringSupport {
    struct CollectionRewriteState {
        var listExprIDs: Set<Int32> = []
        var setExprIDs: Set<Int32> = []
        var mapExprIDs: Set<Int32> = []
        var arrayExprIDs: Set<Int32> = []
        var sequenceExprIDs: Set<Int32> = []
        var rangeExprIDs: Set<Int32> = []
        var charRangeExprIDs: Set<Int32> = []
        var ulongRangeExprIDs: Set<Int32> = []
        var stringExprIDs: Set<Int32> = []
        var fileExprIDs: Set<Int32> = []
        var pathExprIDs: Set<Int32> = []

        var listIteratorExprIDs: Set<Int32> = []
        var mapIteratorExprIDs: Set<Int32> = []
        var iteratorBuilderExprIDs: Set<Int32> = []
        var indexingIterableExprIDs: Set<Int32> = []
        var indexingIterableIteratorExprIDs: Set<Int32> = []
        var ulongRangeIteratorExprIDs: Set<Int32> = []

        mutating func tagListResult(_ result: KIRExprID?, temporary: KIRExprID? = nil) {
            guard let result else { return }
            listExprIDs.insert(result.rawValue)
            if let temporary {
                listExprIDs.insert(temporary.rawValue)
            }
        }

        mutating func tagMapResult(_ result: KIRExprID?, temporary: KIRExprID? = nil) {
            guard let result else { return }
            mapExprIDs.insert(result.rawValue)
            if let temporary {
                mapExprIDs.insert(temporary.rawValue)
            }
        }

        mutating func propagateCopy(from: KIRExprID, to: KIRExprID) {
            // Mutable locals reuse their expression ID. A copy replaces its
            // value, so facts about the previous value must not survive it.
            func copyMembership(_ expressions: inout Set<Int32>) {
                if expressions.contains(from.rawValue) {
                    expressions.insert(to.rawValue)
                } else {
                    expressions.remove(to.rawValue)
                }
            }

            copyMembership(&listExprIDs)
            copyMembership(&setExprIDs)
            copyMembership(&mapExprIDs)
            copyMembership(&arrayExprIDs)
            copyMembership(&sequenceExprIDs)
            copyMembership(&rangeExprIDs)
            copyMembership(&charRangeExprIDs)
            copyMembership(&ulongRangeExprIDs)
            copyMembership(&stringExprIDs)
            copyMembership(&listIteratorExprIDs)
            copyMembership(&mapIteratorExprIDs)
            copyMembership(&fileExprIDs)
            copyMembership(&pathExprIDs)
            copyMembership(&iteratorBuilderExprIDs)
            copyMembership(&indexingIterableExprIDs)
            copyMembership(&indexingIterableIteratorExprIDs)
            copyMembership(&ulongRangeIteratorExprIDs)
        }
    }
}
