// BUG-233: `map[k] = v` goes through the bundled inline `kotlin.collections.set`,
// which forwards to `put`. When the stdlib is consumed as a .kklib the inlined
// call carried no callee symbol, so the erased type-parameter slots were invisible
// to the ABI boxing rules and Double/Float/Char/Boolean were stored raw.
fun main() {
    val values: MutableMap<String, Double> = mutableMapOf()
    values["d"] = 1.5
    println(values)

    val floats: MutableMap<String, Float> = mutableMapOf()
    floats["f"] = 1.5f
    println(floats)

    val chars: MutableMap<String, Char> = mutableMapOf()
    chars["c"] = 'x'
    println(chars)

    val booleans: MutableMap<String, Boolean> = mutableMapOf()
    booleans["t"] = true
    booleans["f"] = false
    println(booleans)

    val ints: MutableMap<String, Int> = mutableMapOf()
    ints["i"] = 7
    println(ints)

    val longs: MutableMap<String, Long> = mutableMapOf()
    longs["l"] = 7L
    println(longs)

    // Primitive keys go through the same erased slot.
    val doubleKeys: MutableMap<Double, String> = mutableMapOf()
    doubleKeys[1.5] = "a"
    doubleKeys[2.75] = "b"
    println(doubleKeys)
    println(doubleKeys[1.5])
    println(doubleKeys.keys)

    val charKeys: MutableMap<Char, Int> = mutableMapOf()
    charKeys['x'] = 1
    println(charKeys)
    println(charKeys.keys)

    val booleanKeys: MutableMap<Boolean, Int> = mutableMapOf()
    booleanKeys[true] = 1
    println(booleanKeys)

    // getOrPut is another bundled inline extension forwarding to put.
    // Reading an existing entry back through getOrPut is BUG-234 and is left out.
    val lazyValues: MutableMap<String, Double> = mutableMapOf()
    println(lazyValues.getOrPut("k") { 2.5 })
    println(lazyValues)

    // Entries stored via `[]=` must compare equal to entries stored via put.
    val viaSet: MutableMap<String, Double> = mutableMapOf()
    viaSet["k"] = 1.5
    val viaPut: MutableMap<String, Double> = mutableMapOf()
    viaPut.put("k", 1.5)
    println(viaSet == viaPut)
    println(viaSet.containsValue(1.5))
    println(viaSet["k"] == 1.5)
    println(viaSet.values.toList()[0] == 1.5)
}
