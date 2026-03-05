import Foundation

// Rewrites collection factory and member calls to runtime ABI calls.
final class CollectionLiteralLoweringPass: LoweringPass {
    static let name = "CollectionLiteralLowering"
}
