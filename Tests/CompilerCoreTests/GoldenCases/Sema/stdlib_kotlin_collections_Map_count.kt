import kotlin.collections.AbstractMap
import kotlin.collections.Map
import kotlin.collections.Set

class ObservedMap : AbstractMap<String?, Int?>() {
    override val entries: Set<Map.Entry<String?, Int?>>
        get() = emptyMap<String?, Int?>().entries

    override val size: Int
        get() = 2

}

fun mapCount(values: Map<String?, Int?>): Int {
    return values.count()
}

fun mapPredicateCount(values: Map<String?, Int?>): Int {
    return values.count { it.key == null || it.value == null }
}

fun customMapCount(): Int {
    return ObservedMap().count()
}
