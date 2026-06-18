import Foundation
import VibePetCore

let message = "VibePetSetup ready (bridge protocol v\(VibePetCore.protocolVersion))\n"
FileHandle.standardOutput.write(Data(message.utf8))
