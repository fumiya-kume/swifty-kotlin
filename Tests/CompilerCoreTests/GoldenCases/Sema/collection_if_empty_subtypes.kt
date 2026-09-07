// RF-FIXTURE-020 / KSP-953: ifEmpty / isEmpty resolution on custom
// Collection and Map subtypes — an AbstractCollection subclass and a
// Map-delegation class. Map-delegated members are reached through the Map
// interface parameter because direct member lookup on the delegating class
// misses them (BUG-239). size-override based isEmpty results and fallback
// call counts are executed by the same-name diff case.
class CustomCollection : AbstractCollection<String?>() {
    override val size: Int get() = 1
    override fun iterator(): Iterator<String?> = emptyList<String?>().iterator()
}

class CustomMap : Map<String?, Int?> by mapOf<String?, Int?>("key" to 1) {
    override val size: Int get() = 1
}

fun subtypeResolution(collection: CustomCollection, map: CustomMap) {
    val collectionResult: Any? = collection.ifEmpty { "fallback" }
    val mapResult: Any? = map.ifEmpty { "fallback" }
    val collectionEmpty = collection.isEmpty()
    val checkedCollection: Boolean = collectionEmpty
}

fun isEmptyViaInterface(map: Map<String?, Int?>) {
    val empty = map.isEmpty()
    val checked: Boolean = empty
}
