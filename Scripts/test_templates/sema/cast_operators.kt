package golden.sema

fun unsafeCastSuccess(v: Any): String = v as String

fun safeCastSuccess(v: Any): String? = v as? String

fun safeCastNull(v: Any): Int? = v as? Int
