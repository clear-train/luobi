import Foundation
import Network
let l = try! NWListener(using: .tcp, on: 57321)
l.stateUpdateHandler = { s in print("state: \(s)") }
l.start(queue: .global())
RunLoop.main.run(until: Date().addingTimeInterval(3))
