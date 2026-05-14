extension CollectionLiteralLoweringPass {
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

        var listIteratorExprIDs: Set<Int32> = []
        var mapIteratorExprIDs: Set<Int32> = []
        var stringIteratorExprIDs: Set<Int32> = []
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
            if listExprIDs.contains(from.rawValue) {
                listExprIDs.insert(to.rawValue)
            }
            if setExprIDs.contains(from.rawValue) {
                setExprIDs.insert(to.rawValue)
            }
            if mapExprIDs.contains(from.rawValue) {
                mapExprIDs.insert(to.rawValue)
            }
            if arrayExprIDs.contains(from.rawValue) {
                arrayExprIDs.insert(to.rawValue)
            }
            if sequenceExprIDs.contains(from.rawValue) {
                sequenceExprIDs.insert(to.rawValue)
            }
            if rangeExprIDs.contains(from.rawValue) {
                rangeExprIDs.insert(to.rawValue)
            }
            if charRangeExprIDs.contains(from.rawValue) {
                charRangeExprIDs.insert(to.rawValue)
            }
            if ulongRangeExprIDs.contains(from.rawValue) {
                ulongRangeExprIDs.insert(to.rawValue)
            }
            if stringExprIDs.contains(from.rawValue) {
                stringExprIDs.insert(to.rawValue)
            }
            if listIteratorExprIDs.contains(from.rawValue) {
                listIteratorExprIDs.insert(to.rawValue)
            }
            if mapIteratorExprIDs.contains(from.rawValue) {
                mapIteratorExprIDs.insert(to.rawValue)
            }
            if stringIteratorExprIDs.contains(from.rawValue) {
                stringIteratorExprIDs.insert(to.rawValue)
            }
            if fileExprIDs.contains(from.rawValue) {
                fileExprIDs.insert(to.rawValue)
            }
            if iteratorBuilderExprIDs.contains(from.rawValue) {
                iteratorBuilderExprIDs.insert(to.rawValue)
            }
            if indexingIterableExprIDs.contains(from.rawValue) {
                indexingIterableExprIDs.insert(to.rawValue)
            }
            if indexingIterableIteratorExprIDs.contains(from.rawValue) {
                indexingIterableIteratorExprIDs.insert(to.rawValue)
            }
            if ulongRangeIteratorExprIDs.contains(from.rawValue) {
                ulongRangeIteratorExprIDs.insert(to.rawValue)
            }
        }
    }
}
