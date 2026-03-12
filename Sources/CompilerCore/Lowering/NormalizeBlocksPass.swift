import Foundation

final class NormalizeBlocksPass: LoweringPass {
    static let name = "NormalizeBlocks"

    func shouldRun(module: KIRModule, ctx _: KIRContext) -> Bool {
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                switch instruction {
                case .beginBlock, .endBlock:
                    return true
                default:
                    break
                }
            }
            // Also run if any function body doesn't end with a return
            if let last = function.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    return true
                }
            } else {
                return true
            }
        }
        return false
    }

    func run(module: KIRModule, ctx _: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.replaceBody(function.body.filter { instruction in
                switch instruction {
                case .beginBlock, .endBlock:
                    false
                default:
                    true
                }
            })
            if let last = updated.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    var normalizedBody = updated.body
                    normalizedBody.append(.returnUnit)
                    updated.replaceBody(normalizedBody)
                }
            } else {
                updated.replaceBody([.returnUnit])
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}
