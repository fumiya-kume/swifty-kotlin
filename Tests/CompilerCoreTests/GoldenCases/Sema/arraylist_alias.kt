// `ArrayList<E>` is a typealias for `MutableList<E>`
// (Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt).
// This case verifies only alias resolution: parameter / return / property
// types, nested type arguments, upper bounds, extension receivers, and
// MutableList / List compatibility. Element mutation, indexed access and
// printing are executed by Scripts/diff_cases/arraylist_alias.kt and
// ksp627_collection_aliases.kt.

fun processList(list: ArrayList<String>) {}

fun createList(): ArrayList<Int> {
    return ArrayList<Int>()
}

class Container {
    val items: ArrayList<String> = ArrayList()
    val numbers: ArrayList<Int> = ArrayList<Int>()
}

fun <T : ArrayList<String>> constrain(list: T): T {
    return list
}

fun ArrayList<String>.customExtension(): String {
    return "extended"
}

fun main() {
    // Constructor inference from explicit type arguments alone, checked by the
    // assignments and call below rather than an expected type.
    val explicit = ArrayList<String>()
    val explicitAsMutable: MutableList<String> = explicit
    processList(explicit)

    // Expected-type inference through the alias and through MutableList.
    val fromAlias: ArrayList<Double> = ArrayList()
    val fromMutable: MutableList<Boolean> = ArrayList()

    // A value declared as MutableList satisfies an ArrayList parameter,
    // because the alias resolves to the same type.
    processList(explicitAsMutable)

    // List (read-only) compatibility.
    val asReadOnly: List<String> = ArrayList()

    // Return type propagation.
    val created = createList()
    val createdAsMutable: MutableList<Int> = created

    // Property type propagation.
    val holder = Container()
    val items: MutableList<String> = holder.items
    val numbers: ArrayList<Int> = holder.numbers

    // Nested type arguments.
    val nested: ArrayList<ArrayList<String>> = ArrayList()
    val nestedAsMutable: MutableList<MutableList<String>> = nested

    // Upper-bound constraint and return propagation.
    val constrained = constrain(explicit)
    val constrainedAsMutable: MutableList<String> = constrained

    // Extension receiver on the alias.
    val extended: String = explicit.customExtension()
}
