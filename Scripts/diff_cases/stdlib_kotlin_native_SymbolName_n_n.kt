// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Native-only and unavailable in the JVM kotlinc reference environment.

import kotlin.native.SymbolName

@SymbolName("symbol_name_probe")
fun symbolNameProbe(): Int = 42

fun main() {
    println(symbolNameProbe())
}
