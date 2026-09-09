package golden.sema

import kotlin.collections.AbstractMutableMap
import kotlin.collections.Map
import kotlin.collections.MutableCollection
import kotlin.collections.MutableSet

abstract class ProbeMutableMap : AbstractMutableMap<String, Int>() {}

fun abstractMutableMapSurface(
    values: AbstractMutableMap<String, Int>,
    source: Map<String, Int>,
    key: String,
    amount: Int
): Int? {
    values.put(key, amount)
    values.putAll(source)
    val removed = values.remove(key)
    values.clear()
    val keys: MutableSet<String> = values.keys
    val valuesView: MutableCollection<Int> = values.values
    keys.contains(key)
    valuesView.contains(amount)
    return removed
}
