// SKIP-DIFF
fun traceValue(tag: String): String {
    println("value:$tag")
    return tag
}

fun makeTaggedBuilder(tag: String): StringBuilder {
    println("make:$tag")
    return StringBuilder(tag)
}

fun labeledResult(): String = run {
    if (true) return@run "labeled-return"
    "unreachable"
}

fun main() {
    val nullableInput: String? = "hello"
    println(nullableInput?.let { it.uppercase() })
    println((null as String?)?.let { it.uppercase() })

    println(traceValue("takeIf").takeIf { it.startsWith("take") })
    println(traceValue("takeUnless").takeUnless { it.endsWith("less") })

    val alsoResult = makeTaggedBuilder("once").also { it.append(":also") }.toString()
    println(alsoResult)

    val withResult = with(traceValue("with")) {
        this + ":with"
    }
    println(withResult)

    val nested = "kotlin"
        .takeIf { it.startsWith("kot") }
        ?.let { it.takeUnless { inner -> inner.length > 10 } }
    println(nested)

    val applyResult = makeTaggedBuilder("apply").apply {
        append(":done")
    }.toString()
    println(applyResult)

    println(labeledResult())
}
