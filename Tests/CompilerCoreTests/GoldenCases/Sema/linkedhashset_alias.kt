// `LinkedHashSet<E>` is a source-backed open nominal class
// (Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt).
// This case verifies only the nominal type and its factories: parameter /
// return / property types, `LinkedHashSet()` constructor and `linkedSetOf`
// factory inference, nested type arguments, upper bound, extension receiver,
// and Set / MutableSet compatibility. Subclassing is verified separately in
// linkedhashset_inheritance.kt; mutation and membership behavior are executed
// by Scripts/diff_cases/ksp627_collection_aliases.kt and
// bug196_linkedhashset_subclass.kt.

fun processLinkedSet(set: LinkedHashSet<String>) {}

fun createLinkedSet(): LinkedHashSet<Int> {
    return LinkedHashSet<Int>()
}

class OrderedTags {
    val tags: LinkedHashSet<String> = LinkedHashSet()
    val ids: LinkedHashSet<Int> = LinkedHashSet<Int>()
}

fun <T : LinkedHashSet<String>> constrainLinked(set: T): T {
    return set
}

fun LinkedHashSet<String>.linkedExtension(): String {
    return "linked"
}

fun main() {
    // Constructor inference from explicit type arguments alone, checked by the
    // assignments and call below rather than an expected type.
    val explicit = LinkedHashSet<String>()
    val explicitAsMutable: MutableSet<String> = explicit
    processLinkedSet(explicit)

    // Expected-type inference through the nominal type (constructor and
    // linkedSetOf factory) and through MutableSet.
    val fromNominal: LinkedHashSet<Double> = LinkedHashSet()
    val fromFactory: LinkedHashSet<Double> = linkedSetOf()
    val fromMutable: MutableSet<Boolean> = LinkedHashSet()

    // Set (read-only) compatibility.
    val asReadOnly: Set<String> = LinkedHashSet()

    // Return type propagation.
    val created = createLinkedSet()
    val createdAsMutable: MutableSet<Int> = created

    // Property type propagation.
    val holder = OrderedTags()
    val tags: MutableSet<String> = holder.tags
    val ids: LinkedHashSet<Int> = holder.ids

    // Nested type arguments.
    val nested: LinkedHashSet<LinkedHashSet<String>> = LinkedHashSet()
    val nestedAsMutable: MutableSet<LinkedHashSet<String>> = nested

    // Upper-bound constraint and return propagation.
    val constrained = constrainLinked(explicit)
    val constrainedAsMutable: MutableSet<String> = constrained

    // Extension receiver on the nominal type.
    val extended: String = explicit.linkedExtension()
}
