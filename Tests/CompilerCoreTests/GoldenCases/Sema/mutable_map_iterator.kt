// RF-FIXTURE-019: MutableMap.iterator() yields a MutableIterator over
// MutableMap.MutableEntry — hasNext / next / entry.setValue / remove.
fun iterateEntries(map: MutableMap<String, Int?>) {
    val iterator = map.iterator()
    val checkedIterator: MutableIterator<MutableMap.MutableEntry<String, Int?>> = iterator
    if (iterator.hasNext()) {
        val entry = iterator.next()
        val key = entry.key
        val checkedKey: String = key
        entry.setValue(999)
        iterator.remove()
    }
}
