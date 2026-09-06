package golden.sema

import kotlin.native.SymbolName

@SymbolName("golden_symbol_name")
fun symbolNameProbe(): Int = 42

fun useSymbolNameProbe(): Int = symbolNameProbe()
