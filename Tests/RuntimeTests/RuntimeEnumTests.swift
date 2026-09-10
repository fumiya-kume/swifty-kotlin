@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeEnumTests {
    @Test
    func emptyEnumEntriesUseDistinctStableCacheKeys() {
        let firstEnumID = 91_001
        let secondEnumID = 91_002

        let firstEntries = kk_enum_make_entries_list_cached(kk_array_new(0), 0, firstEnumID)
        let firstEntriesAgain = kk_enum_make_entries_list_cached(kk_array_new(0), 0, firstEnumID)
        let secondEntries = kk_enum_make_entries_list_cached(kk_array_new(0), 0, secondEnumID)

        #expect(firstEntries == firstEntriesAgain)
        #expect(firstEntries != secondEntries)
    }

    @Test
    func enumBoxEqualityIncludesEnumClassIdentity() {
        let firstEnumEntry = kk_enum_box_ordinal(0, 0, 91_101)
        let sameEnumEntry = kk_enum_box_ordinal(0, 0, 91_101)
        let otherEnumEntry = kk_enum_box_ordinal(0, 0, 91_102)

        #expect(kk_unbox_bool(kk_any_member_equals(firstEnumEntry, sameEnumEntry)) == 1)
        #expect(kk_unbox_bool(kk_any_member_equals(firstEnumEntry, otherEnumEntry)) == 0)
        #expect(kk_unbox_bool(kk_any_member_equals(firstEnumEntry, kk_box_int(0))) == 0)
    }
}
