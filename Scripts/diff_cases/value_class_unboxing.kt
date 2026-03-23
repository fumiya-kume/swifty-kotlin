@JvmInline
value class Email(val value: String)

@JvmInline
value class UserId(val id: Int)

fun sendEmail(email: Email) = println("Sending to ${email.value}")
fun processId(id: UserId) = println("Processing ${id.id}")

fun main() {
    val email = Email("test@example.com")
    sendEmail(email)
    val id = UserId(42)
    processId(id)
    println(email.value)
    println(id.id)
}
