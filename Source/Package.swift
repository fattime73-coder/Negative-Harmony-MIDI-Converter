// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"NegativeHarmonyMIDIConverter",platforms:[.macOS(.v13)],products:[.executable(name:"NegativeHarmony",targets:["NegativeHarmony"])],targets:[.executableTarget(name:"NegativeHarmony",path:"Sources/NegativeHarmony")])
