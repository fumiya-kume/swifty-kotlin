package golden.sema

class Handled
class Unhandled

fun tryCatchExpr(flag: Boolean): String =
    try { if (flag) "ok" else throw Exception("fail") }
    catch (e: Exception) { "error" }

fun tryMultiCatch(): String =
    try { "ok" }
    catch (e: IllegalArgumentException) { "arg" }
    catch (e: Exception) { "other" }

fun tryFinally(): String =
    try { "result" }
    finally { }

fun tryCompletionCriteria(): String {
    val x: String = try { "ok" } catch (e: Exception) { "err" }
    return x
}

fun tryFinallyIgnoresValue(): String =
    try { "ok" }
    finally { 123 }

fun tryMultiCatchJoin(flag: Int): Any? =
    try {
        if (flag == 0) "ok" else if (flag == 1) throw Handled() else throw Unhandled()
    } catch (e: Handled) {
        "handled"
    } catch (e: Unhandled) {
        7
    }

fun tryPartialCatchRethrow(flag: Boolean): Int {
    var x: Int
    try {
        if (flag) throw Handled() else throw Unhandled()
    } catch (e: Handled) {
        x = 7
    }
    return x
}
