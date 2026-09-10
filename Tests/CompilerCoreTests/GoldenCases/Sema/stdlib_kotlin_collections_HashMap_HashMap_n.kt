package golden.sema

fun hashMapReceiverMembers(map: HashMap<String, Int?>, other: Map<String, Int?>): Any? {
    map.clear()
    map.containsKey("key")
    map.containsValue(null)
    map.entries
    map.equals(other)
    map.get("key")
    map.hashCode()
    map.isEmpty()
    map.keys
    map.put("key", 1)
    map.putAll(other)
    map.remove("key")
    map.size
    map.toString()
    map.values
    return map
}
