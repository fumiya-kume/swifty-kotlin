fun traceValue(tag: String): String {
    println("value:$tag")
    return tag
}

fun makeTaggedBuilder(tag: String): StringBuilder {
    println("make:$tag")
    return StringBuilder(tag)
}

fun labeledResult(): String = run outer@{
    "label".let {
        if (it.length == 5) return@outer "labeled-return"
        "unreachable"
    }
}

fun main() {
    val nullableInput: String? = "hello"
    println(nullableInput?.let { it.uppercase() })
    println((null as String?)?.let { it.uppercase() })

    println(traceValue("takeIf").takeIf { it.startsWith("take") })
    println(traceValue("takeUnless").takeUnless { it.endsWith("less") })

    val alsoResult = makeTaggedBuilder("once").also { it.append(":also") }.toString()
    println(alsoResult)

    val withResult = with(makeTaggedBuilder("with")) {
        append(":with")
        toString()
    }
    println(withResult)

    val nested = "kotlin"
        .takeIf { it.startsWith("kot") }
        ?.let { it.takeUnless { inner -> inner.length > 10 } }
    println(nested)

    val applyRunResult = makeTaggedBuilder("apply").apply {
        append(":run")
    }.run {
        append(":done")
        toString()
    }
    println(applyRunResult)

    println(labeledResult())
}
