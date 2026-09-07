// `LinkedHashMap<K, V>` is a typealias for `MutableMap<K, V>`
// (Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt).
// This case verifies only alias resolution: constructor type-argument
// inference, parameter / return / property types, and MutableMap compatibility.
// Updates, lookups, entries HOFs and iteration are executed by
// Scripts/diff_cases/linkedhashmap_alias.kt and map_entries_hof.kt.

fun processLinkedMap(map: LinkedHashMap<String, Int>) {}

fun createLinkedMap(): LinkedHashMap<Int, String> {
    return LinkedHashMap<Int, String>()
}

class OrderedMapHolder {
    val scores: LinkedHashMap<String, Int> = LinkedHashMap()
    val labels: LinkedHashMap<Int, String> = LinkedHashMap<Int, String>()
}

fun main() {
    // Constructor inference from explicit type arguments alone: no expected
    // type here, so the inferred type is checked by the assignment and the
    // argument below instead.
    val explicit = LinkedHashMap<String, Int>()
    val explicitAsMutable: MutableMap<String, Int> = explicit
    processLinkedMap(explicit)

    // Type-argument inference from the expected type, through the alias and
    // through MutableMap.
    val fromAlias: LinkedHashMap<Double, Boolean> = LinkedHashMap()
    val fromMutable: MutableMap<Int, String> = LinkedHashMap()

    // A value declared as MutableMap satisfies a LinkedHashMap parameter,
    // because the alias resolves to the same type. kotlinc rejects this (there
    // LinkedHashMap is the java.util class), so it stays a Sema-only assertion
    // of KSwiftK's alias model and must not be copied into a diff case.
    processLinkedMap(explicitAsMutable)

    // Return type propagation.
    val created = createLinkedMap()
    val createdAsMutable: MutableMap<Int, String> = created

    // Property type propagation.
    val holder = OrderedMapHolder()
    val scores: MutableMap<String, Int> = holder.scores
    val labels: LinkedHashMap<Int, String> = holder.labels
}
