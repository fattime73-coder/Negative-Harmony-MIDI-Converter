import Foundation
var checks = 0
func check(_ condition: Bool,_ label: String) { checks += 1; if !condition { fatalError("FAIL: \(label)") } }
func signature(_ n: MIDINote) -> String { "\(n.track):\(n.on):\(n.off):\(n.start):\(n.end):\(n.velocity):\(n.channel)" }
func converted(_ file: MIDIFile,_ s: HarmonySettings = HarmonySettings(),_ roles: [Int:TrackRole] = [:]) throws -> MIDIFile { try HarmonyEngine.convert(file,settings:s,roles:roles).file }
func fixture(_ pitches: [Int],channel: UInt8 = 0) -> MIDIFile {
    var e = pitches.enumerated().map { MIDIEvent(tick:$0.offset*480,bytes:[0x90|channel,UInt8($0.element),UInt8(60+$0.offset)]) } + pitches.enumerated().map { MIDIEvent(tick:$0.offset*480+240,bytes:[0x80|channel,UInt8($0.element),37]) }
    e.sort { $0.tick < $1.tick }; return MIDIFile(format:0,tracks:[MIDITrack(events:e)])
}
let demo = MIDIFile.demo()
let roundtrip = try MIDIFile(data:demo.data())
check(roundtrip.data() == demo.data(),"SMF writer round trip")
let input = try demo.notes(), out = try converted(demo), notes = try out.notes()
check(input.map(signature) == notes.map(signature),"Timing, velocity, channel, pairing preservation")
for (a,b) in zip(input,notes) { check(pc(b.pitch) == pc(7-a.pitch),"PC inversion") }
let melody = try converted(fixture([60,67,62])).notes()
check(melody.map { pc($0.pitch) } == [7,0,5],"C-G-D -> G-C-F")
for tonic in 0..<12 {
    var s = HarmonySettings(); s.tonic = tonic
    let f = fixture(Array(0...127))
    let first = try converted(f,s); let second = try converted(first,s)
    check(try second.notes().map { pc($0.pitch) } == f.notes().map { pc($0.pitch) },"Double inversion key \(tonic)")
    check(try first.notes().allSatisfy { 0...127 ~= $0.pitch },"MIDI pitch bounds")
}
for sum in 0..<12 {
    var s = HarmonySettings(); s.axis = .custom; s.customSum = sum
    check(try converted(fixture([0,60,127]),s).notes().map { pc($0.pitch) } == [pc(sum),pc(sum-60),pc(sum-127)],"custom sum")
}
let chordCases: [(String,[Int])] = [("C",[60,64,67]),("Cm",[60,63,67]),("C7",[60,64,67,70]),("Cmaj7",[60,64,67,71]),("C9",[60,62,64,67,70]),("C11",[60,62,64,65,67,70]),("C13",[60,62,64,65,67,69,70]),("Csus4",[60,65,67]),("Cdim",[60,63,66]),("Caug",[60,64,68]),("Cadd9",[60,62,64,67]),("C/E",[64,67,72])]
for (name,pitches) in chordCases { check(ChordAnalyzer.label(pitches) == name,"chord \(name)") }
let expected = ["Cm","E♭","Gm","Fm6"]
for (i,name) in expected.enumerated() { check(ChordAnalyzer.label(notes.filter { $0.track == 2 && $0.start == i*1920 }.map(\.pitch)).split(separator:"/").first == Substring(name),"negative chord \(name)") }
var s = HarmonySettings(); s.blend = 0
check(try converted(demo,s).data() == demo.data(),"Blend 0 exact events")
s.blend = 50
let b1 = try converted(demo,s), b2 = try converted(demo,s)
check(b1.data() == b2.data(),"Blend deterministic")
check(try b1.notes().map(signature) == input.map(signature),"Blend timing preservation")
s = HarmonySettings(); s.scope = .melody
let onlyMelody = try converted(demo,s,[1:.melody,2:.chords])
check(onlyMelody.tracks[2].events == demo.tracks[2].events,"Melody only leaves chords")
s.scope = .chords
let onlyChords = try converted(demo,s,[1:.melody,2:.chords])
check(onlyChords.tracks[1].events == demo.tracks[1].events,"Chords only leaves melody")
let drums = fixture([36,38,42],channel:9)
check(try converted(drums).data() == drums.data(),"Percussion bypass")
check(try converted(demo,HarmonySettings(),[1:.bypass,2:.bypass]).data() == demo.data(),"Bypass")
// Running status, velocity-zero note-off, tempo, program, CC, pitch bend, sysex.
let raw: [UInt8] = [0,0xff,0x51,3,7,0xa1,0x20, 0,0xc0,4, 0,0xb0,64,127, 0,0xe0,0,64, 0,0xf0,2,0x7d,0xf7, 0,0x90,60,99, 0x83,0x60,60,0, 0,0xff,0x2f,0]
let rawFile = Data(Array("MThd".utf8)+[0,0,0,6,0,0,0,1,1,0xe0]+Array("MTrk".utf8)+bigEndian(raw.count,4)+raw)
let rf = try MIDIFile(data:rawFile), rc = try converted(rf)
check(try rc.notes().first!.end == 480,"Running status and zero-off")
for i in [0,1,2,3,4,7] { check(rf.tracks[0].events[i] == rc.tracks[0].events[i],"Non-note event preserved") }
// Repeated same pitch, different velocities and release velocity.
let repeated = MIDIFile(format:0,tracks:[MIDITrack(events:[MIDIEvent(tick:0,bytes:[0x90,60,80]),MIDIEvent(tick:240,bytes:[0x80,60,21]),MIDIEvent(tick:240,bytes:[0x90,60,90]),MIDIEvent(tick:480,bytes:[0x90,60,0])])])
check(try converted(repeated).notes().map(signature) == repeated.notes().map(signature),"Repeated pairing")
// First inversion C/E -> first inversion Cm/Eb.
let inv = MIDIFile(format:0,tracks:[MIDITrack(events:[64,67,72].map { MIDIEvent(tick:0,bytes:[0x90,UInt8($0),80]) } + [64,67,72].map { MIDIEvent(tick:480,bytes:[0x80,UInt8($0),0]) })])
s = HarmonySettings(); s.preserveInversion = true
let invNotes = try converted(inv,s,[0:.chords]).notes()
check(ChordAnalyzer.identify(invNotes.map(\.pitch))?.inversion == 1,"Inversion preserved")
check(ChordAnalyzer.identify([62,64,67,70,72])?.inversion == 4,"Ninth in bass is fourth inversion")
// Reject pitch collisions that would change original note durations at intermediate Blend.
let collision = MIDIFile(format:0,tracks:[MIDITrack(events:[MIDIEvent(tick:0,bytes:[0x90,60,80]),MIDIEvent(tick:10,bytes:[0x90,67,80]),MIDIEvent(tick:20,bytes:[0x80,67,0]),MIDIEvent(tick:30,bytes:[0x80,60,0])])])
s = HarmonySettings(); s.blend = 50
let collisionResult = try converted(collision,s)
check(try collisionResult.notes().map(signature) == collision.notes().map(signature),"Avoid active pitch collisions")
for malformed in [Data(),Data("Not MIDI".utf8),demo.data().prefix(22)] {
    do { _ = try MIDIFile(data:malformed); fatalError("Malformed accepted") } catch { checks += 1 }
}
// Every byte truncation must either parse completely or fail cleanly.
for length in 0..<demo.data().count { do { _ = try MIDIFile(data:demo.data().prefix(length)); fatalError("Truncated accepted") } catch { checks += 1 } }
if CommandLine.arguments.count > 1 {
    let dir = URL(fileURLWithPath:CommandLine.arguments[1]); try demo.data().write(to:dir.appendingPathComponent("C-Major-Demo.mid")); try out.data().write(to:dir.appendingPathComponent("C-Major-Negative.mid"))
}
print("PASS: \(checks) checks")
