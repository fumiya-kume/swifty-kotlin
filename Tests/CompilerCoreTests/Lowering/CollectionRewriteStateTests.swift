#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CollectionRewriteStateTests {
    private typealias State = CollectionLiteralLoweringSupport.CollectionRewriteState

    private var classifications: [WritableKeyPath<State, Set<Int32>>] {
        [
            \.listExprIDs, \.setExprIDs, \.mapExprIDs, \.arrayExprIDs,
            \.sequenceExprIDs, \.rangeExprIDs, \.charRangeExprIDs,
            \.ulongRangeExprIDs, \.stringExprIDs, \.fileExprIDs, \.pathExprIDs,
            \.listIteratorExprIDs, \.mapIteratorExprIDs, \.iteratorBuilderExprIDs,
            \.indexingIterableExprIDs, \.indexingIterableIteratorExprIDs,
            \.ulongRangeIteratorExprIDs,
        ]
    }

    @Test
    func copiesPreserveEachClassificationThroughMultipleAliases() {
        let source = KIRExprID(rawValue: 1)
        let alias = KIRExprID(rawValue: 2)
        let secondAlias = KIRExprID(rawValue: 3)
        for classification in classifications {
            var state = State()
            state[keyPath: classification].insert(source.rawValue)
            state.propagateCopy(from: source, to: alias)
            state.propagateCopy(from: alias, to: secondAlias)

            for observed in classifications {
                let expected: Set<Int32> = observed == classification ? [1, 2, 3] : []
                #expect(state[keyPath: observed] == expected)
            }
        }
    }

    @Test
    func rangeCopiesRetainGeneralAndSpecializedFactsTogether() {
        let charRange = KIRExprID(rawValue: 1)
        let unsignedRange = KIRExprID(rawValue: 2)
        let charAlias = KIRExprID(rawValue: 3)
        let unsignedAlias = KIRExprID(rawValue: 4)
        var state = State()
        state.rangeExprIDs = [1, 2]
        state.charRangeExprIDs = [1]
        state.ulongRangeExprIDs = [2]

        state.propagateCopy(from: charRange, to: charAlias)
        state.propagateCopy(from: unsignedRange, to: unsignedAlias)

        #expect(state.rangeExprIDs == [1, 2, 3, 4])
        #expect(state.charRangeExprIDs == [1, 3])
        #expect(state.ulongRangeExprIDs == [2, 4])
    }

    @Test
    func reassigningStorageReplacesItsPreviousClassification() {
        let list = KIRExprID(rawValue: 1)
        let map = KIRExprID(rawValue: 2)
        let storage = KIRExprID(rawValue: 3)
        let priorAlias = KIRExprID(rawValue: 4)
        var state = State()
        state.listExprIDs = [list.rawValue]
        state.mapExprIDs = [map.rawValue]

        state.propagateCopy(from: list, to: storage)
        state.propagateCopy(from: storage, to: priorAlias)
        state.propagateCopy(from: map, to: storage)

        #expect(state.listExprIDs == [list.rawValue, priorAlias.rawValue])
        #expect(state.mapExprIDs == [map.rawValue, storage.rawValue])
    }

    @Test
    func reassigningAnUnknownValueClearsEveryRuntimeClassification() {
        let unknown = KIRExprID(rawValue: 1)
        let storage = KIRExprID(rawValue: 2)
        for classification in classifications {
            var state = State()
            state[keyPath: classification].insert(storage.rawValue)

            state.propagateCopy(from: unknown, to: storage)

            for observed in classifications {
                #expect(state[keyPath: observed].isEmpty)
            }
        }
    }

    @Test
    func selfCopyPreservesOverlappingRangeFacts() {
        let range = KIRExprID(rawValue: 1)
        var state = State()
        state.rangeExprIDs = [1]
        state.ulongRangeExprIDs = [1]

        state.propagateCopy(from: range, to: range)

        #expect(state.rangeExprIDs == [1])
        #expect(state.ulongRangeExprIDs == [1])
        #expect(state.charRangeExprIDs.isEmpty)
    }
}
#endif
