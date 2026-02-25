package golden.sema

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

fun tryCatchFinally(): String =
    try { "ok" }
    catch (e: Exception) { "err" }
    finally { }

val propTryCatch: String =
    try { "ok" }
    catch (e: Exception) { "err" }

val propTryFinally: String =
    try { "result" }
    finally { }
