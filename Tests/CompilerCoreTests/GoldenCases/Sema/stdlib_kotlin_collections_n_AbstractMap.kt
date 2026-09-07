package golden.sema

import kotlin.collections.AbstractMap
import kotlin.collections.Map
import kotlin.collections.Set

class ProbeMap : AbstractMap<String, Int?>() {
    override val entries: Set<Map.Entry<String, Int?>>
        get() = emptyMap<String, Int?>().entries
}

fun readMap(values: Map<String, Int?>): Int? {
    values["missing"]
    values.containsKey("missing")
    values.containsValue(null)
    values.entries
    values.keys
    values.values
    values.isEmpty()
    values.hashCode()
    return values["value"]
}
