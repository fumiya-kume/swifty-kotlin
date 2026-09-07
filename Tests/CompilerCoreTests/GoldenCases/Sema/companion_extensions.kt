// RF-FIXTURE-021: extension functions and extension properties on unnamed
// (Companion) and named (Factory) companion objects — declaration and call
// sites through the class name.
package golden.sema

class NetworkClient {
    companion object
}

fun NetworkClient.Companion.createDefault(): NetworkClient = NetworkClient()
val NetworkClient.Companion.defaultTimeout: Int get() = 30000

class FileManager {
    companion object Factory
}

fun FileManager.Factory.createFile(): FileManager = FileManager()
val FileManager.Factory.maxFiles: Int get() = 1000

fun useExtensions() {
    val client = NetworkClient.createDefault()
    val checkedClient: NetworkClient = client
    val timeout = NetworkClient.defaultTimeout
    val checkedTimeout: Int = timeout
    val file = FileManager.createFile()
    val checkedFile: FileManager = file
    val max = FileManager.maxFiles
    val checkedMax: Int = max
}
