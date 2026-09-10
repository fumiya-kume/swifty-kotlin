// RF-FIXTURE-015: File.useLines takes a (List<out String>) -> R block and
// propagates the generic R to the call result (List<String> and Int here).
// File construction and the count/toList calls are vehicles for the result
// type; execution is covered by Scripts/diff_cases/file_uselines.kt.
package golden.sema

import java.io.File

fun collectLines(file: File): List<String> {
    return file.useLines { lines ->
        lines.toList()
    }
}

fun countLines(file: File): Int {
    return file.useLines { lines ->
        lines.count()
    }
}
