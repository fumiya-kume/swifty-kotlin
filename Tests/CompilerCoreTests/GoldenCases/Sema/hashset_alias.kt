// `HashSet<E>` is a source-backed nominal class
// (Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt) —
// unlike the ArrayList / LinkedHashMap typealiases, a `MutableSet`-typed value
// is NOT assignable to a `HashSet` parameter. This case verifies only the
// nominal type and the `hashSetOf` factory: parameter / return / property
// types, expected-type inference, nested type arguments, upper bound,
// extension receiver, and Set / MutableSet compatibility. Mutation and
// membership behavior are executed by
// Scripts/diff_cases/ksp627_collection_aliases.kt.

fun processSet(set: HashSet<String>) {}

fun createSet(): HashSet<Int> {
    return hashSetOf<Int>()
}

class TagContainer {
    val tags: HashSet<String> = hashSetOf()
    val ids: HashSet<Int> = hashSetOf<Int>()
}

fun <T : HashSet<String>> constrain(set: T): T {
    return set
}

fun HashSet<String>.customExtension(): String {
    return "extended"
}

fun main() {
    // Factory inference from explicit type arguments alone, checked by the
    // assignments and call below rather than an expected type.
    val explicit = hashSetOf<String>()
    val explicitAsMutable: MutableSet<String> = explicit
    processSet(explicit)

    // Expected-type inference through the nominal type and through MutableSet.
    val fromNominal: HashSet<Double> = hashSetOf()
    val fromMutable: MutableSet<Boolean> = hashSetOf()

    // Set (read-only) compatibility.
    val asReadOnly: Set<String> = hashSetOf()

    // Return type propagation.
    val created = createSet()
    val createdAsMutable: MutableSet<Int> = created

    // Property type propagation.
    val holder = TagContainer()
    val tags: MutableSet<String> = holder.tags
    val ids: HashSet<Int> = holder.ids

    // Nested type arguments.
    val nested: HashSet<HashSet<String>> = hashSetOf()
    val nestedAsMutable: MutableSet<HashSet<String>> = nested

    // Upper-bound constraint and return propagation.
    val constrained = constrain(explicit)
    val constrainedAsMutable: MutableSet<String> = constrained

    // Extension receiver on the nominal type.
    val extended: String = explicit.customExtension()
}
