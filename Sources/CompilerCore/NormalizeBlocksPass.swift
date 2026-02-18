import Foundation

final class NormalizeBlocksPass: LoweringPass {
    static let name = "NormalizeBlocks"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.filter { instruction in
                switch instruction {
                case .beginBlock, .endBlock:
                    return false
                default:
                    return true
                }
            }
            if let last = updated.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    updated.body.append(.returnUnit)
                }
            } else {
                updated.body = [.returnUnit]
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

