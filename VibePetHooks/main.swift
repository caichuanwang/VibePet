import Foundation
import VibePetCore

let message = "VibePetHooks ready (bridge protocol v\(VibePetCore.protocolVersion))\n"
FileHandle.standardOutput.write(Data(message.utf8))
