package golden.sema

import java.io.File
import kotlin.io.AccessDeniedException

fun catchAccessDenied(): String =
    try {
        val f = File("/protected/file.txt")
        throw AccessDeniedException(f)
    } catch (e: AccessDeniedException) {
        "access denied"
    }

fun catchAccessDeniedWithReason(): String =
    try {
        val f = File("/protected/file.txt")
        throw AccessDeniedException(f, null, "permission denied")
    } catch (e: AccessDeniedException) {
        e.message ?: "no message"
    }
