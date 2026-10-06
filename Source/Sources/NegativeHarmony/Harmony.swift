import Foundation

func pc(_ n: Int) -> Int { (n % 12 + 12) % 12 }
let pitchNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
func noteName(_ n: Int) -> String { "\(pitchNames[pc(n)])\(n / 12 - 1)" }
enum TrackRole: String, CaseIterable { case melody = "メロディ", chords = "コード", bypass = "変換しない" }
enum ConversionScope: String, CaseIterable { case both = "メロディ＋コード", melody = "メロディのみ", chords = "コードのみ" }
enum AxisMode: String, CaseIterable { case classic = "Classic Negative Harmony", tonicDominant = "Tonic–Dominant axis", custom = "Custom axis" }
struct HarmonySettings: Equatable {
    var tonic = 0
    var minor = false
    var axis = AxisMode.classic
    var customSum = 7
    var scope = ConversionScope.both
    var preserveInversion = false
    var autoOctave = true
    var voiceLeading = true
    var blend = 100.0
    var sum: Int { axis == .custom ? customSum : pc(2 * tonic + 7) }
}
struct ChordMatch {
    var root: Int
    var suffix: String
    var intervals: [Int]
    var bass: Int
    var name: String { pitchNames[root] + suffix + (bass == root ? "" : "/" + pitchNames[bass]) }
    var inversion: Int { intervals.firstIndex(of: pc(bass-root)) ?? 0 }
}
struct ChordAnalyzer {
    static let templates: [(String,[Int])] = [
        ("",[0,4,7]),("m",[0,3,7]),("dim",[0,3,6]),("aug",[0,4,8]),("sus2",[0,2,7]),("sus4",[0,5,7]),
        ("6",[0,4,7,9]),("m6",[0,3,7,9]),("7",[0,4,7,10]),("maj7",[0,4,7,11]),("m7",[0,3,7,10]),("m(maj7)",[0,3,7,11]),("m7♭5",[0,3,6,10]),("dim7",[0,3,6,9]),("aug7",[0,4,8,10]),("7sus4",[0,5,7,10]),
        ("add9",[0,2,4,7]),("madd9",[0,2,3,7]),("add11",[0,4,5,7]),("madd11",[0,3,5,7]),("add13",[0,4,7,9]),
        ("9",[0,2,4,7,10]),("maj9",[0,2,4,7,11]),("m9",[0,2,3,7,10]),("9sus4",[0,2,5,7,10]),
        ("11",[0,2,4,5,7,10]),("maj11",[0,2,4,5,7,11]),("m11",[0,2,3,5,7,10]),
        ("13",[0,2,4,5,7,9,10]),("maj13",[0,2,4,5,7,9,11]),("m13",[0,2,3,5,7,9,10]),
        ("13(no11)",[0,2,4,7,9,10]),("maj13(no11)",[0,2,4,7,9,11]),("m13(no11)",[0,2,3,7,9,10]),
        ("7♭9",[0,1,4,7,10]),("7♯9",[0,3,4,7,10]),("7♯11",[0,4,6,7,10]),("7♭13",[0,4,7,8,10])
    ]
    static func inversionOrder(_ intervals: [Int]) -> [Int] {
        var remaining = Set(intervals); var result: [Int] = []
        func take(_ choices: [Int]) {
            if let n = choices.first(where: { remaining.contains($0) }) { result.append(n); remaining.remove(n) }
        }
        take([0]); take([4,3,2,5]); take([7,6,8]); take([10,11])
        for n in [1,2,3,5,6,8,9] where remaining.contains(n) { result.append(n); remaining.remove(n) }
        return result + remaining.sorted()
    }
    static func identify(_ pitches: [Int]) -> ChordMatch? {
        guard let bass = pitches.min() else { return nil }
        let set = Set(pitches.map(pc))
        var candidates: [(Int,ChordMatch)] = []
        for root in 0..<12 where set.contains(root) {
            let relative = Set(set.map { pc($0-root) })
            for (index,t) in templates.enumerated() where relative == Set(t.1) {
                candidates.append(((pc(bass) == root ? 0 : 100) + index,ChordMatch(root:root,suffix:t.0,intervals:inversionOrder(t.1),bass:pc(bass))))
            }
        }
        return candidates.min { $0.0 < $1.0 }?.1
    }
    static func label(_ pitches: [Int]) -> String {
        if let c = identify(pitches) { return c.name }
        return Set(pitches.map(pc)).sorted().map { pitchNames[$0] }.joined(separator:" · ")
    }
}
struct ConversionResult {
    var file: MIDIFile
    var warnings: [String]
}
struct HarmonyEngine {
    static func inferredRole(_ notes: [MIDINote]) -> TrackRole {
        let pitched = notes.filter { $0.channel != 9 }.sorted { $0.start < $1.start }
        var end = -1
        for n in pitched { if n.start < end { return .chords }; end = max(end,n.end) }
        return .melody
    }
    static func convert(_ file: MIDIFile, settings s: HarmonySettings, roles: [Int: TrackRole]) throws -> ConversionResult {
        let notes = try file.notes(); var out = file; var warnings = Set<String>(); var mapping: [Int:Int] = [:]
        for ti in file.tracks.indices {
            let trackNotes = notes.filter { $0.track == ti }
            let role = roles[ti] ?? inferredRole(trackNotes)
            let enabled = role != .bypass && (s.scope == .both || (s.scope == .melody && role == .melody) || (s.scope == .chords && role == .chords))
            guard enabled else { continue }
            for ch in 0..<16 where ch != 9 {
                let channelNotes = trackNotes.filter { $0.channel == ch }
                let grouped = Dictionary(grouping: channelNotes, by: \.start)
                var previous: [Int] = []; var active: [(Int,Int,Int)] = []; var accumulator = 0.0
                for start in grouped.keys.sorted() {
                    let group = grouped[start]!.sorted { ($0.pitch,$0.on) < ($1.pitch,$1.on) }
                    active.removeAll { $0.1 <= start }
                    accumulator += s.blend / 100
                    let transform = accumulator >= 1 - 0.000001
                    if transform { accumulator -= 1 }
                    if !transform {
                        for n in group { mapping[n.id] = n.pitch; active.append((n.pitch,n.end,n.pitch)) }
                        continue
                    }
                    var desiredBass: Int? = nil
                    if s.preserveInversion, role == .chords, let originalChord = ChordAnalyzer.identify(group.map(\.pitch)), let targetChord = ChordAnalyzer.identify(group.map { pc(s.sum - $0.pitch) }) {
                        let i = min(originalChord.inversion,targetChord.intervals.count-1)
                        desiredBass = pc(targetChord.root + targetChord.intervals[i])
                    }
                    let ordered = group.sorted {
                        let a = pc(s.sum - $0.pitch), b = pc(s.sum - $1.pitch)
                        if let bass = desiredBass, (a == bass) != (b == bass) { return a == bass }
                        return ($0.pitch,$0.on) < ($1.pitch,$1.on)
                    }
                    var chosen: [Int] = []; var bassPitch: Int?
                    for (index,n) in ordered.enumerated() {
                        let targetPC = pc(s.sum - n.pitch)
                        // Fixed reflection: MIDI pitch axis near middle C, aligned to tonic.
                        let reflected = 120 + 2 * s.tonic + 7 - n.pitch + (s.axis == .custom ? s.customSum - pc(2*s.tonic+7) : 0)
                        let reference = s.autoOctave ? n.pitch : reflected
                        let candidates = (0...127).filter { p in
                            pc(p) == targetPC && !chosen.contains(p) && !active.contains(where: { $0.0 == p && $0.2 != n.pitch }) && (bassPitch == nil || p > bassPitch!)
                        }
                        guard let best = candidates.min(by: { a,b in
                            func cost(_ p: Int) -> Double {
                                var value = Double(abs(p-reference))
                                if s.voiceLeading && !previous.isEmpty { value += 0.8 * Double(abs(p - previous[min(index,previous.count-1)])) }
                                return value
                            }
                            return cost(a) == cost(b) ? a < b : cost(a) < cost(b)
                        }) else { throw MIDIError.invalid("音域内でノートの重複を回避できません。転回形維持をOFFにするか、トラックを分けてください。") }
                        mapping[n.id] = best; chosen.append(best); active.append((best,n.end,n.pitch))
                        if desiredBass != nil && bassPitch == nil { bassPitch = best }
                    }
                    previous = chosen.sorted()
                }
            }
        }
        for n in notes {
            guard let p = mapping[n.id] else { continue }
            out.tracks[n.track].events[n.on].bytes[1] = UInt8(p)
            out.tracks[n.track].events[n.off].bytes[1] = UInt8(p)
        }
        // Polyphonic key pressure follows its active note when unambiguous.
        for ti in out.tracks.indices {
            for ei in out.tracks[ti].events.indices {
                let e = out.tracks[ti].events[ei]
                guard e.bytes.count == 3 && e.bytes[0] & 0xf0 == 0xa0 else { continue }
                let matches = notes.filter { $0.track == ti && $0.channel == Int(e.bytes[0]&15) && $0.pitch == Int(e.bytes[1]) && $0.start <= e.tick && $0.end > e.tick }
                let targets = Set(matches.map { mapping[$0.id] ?? $0.pitch })
                if targets.count == 1, let p = targets.first { out.tracks[ti].events[ei].bytes[1] = UInt8(p) }
                else if targets.count > 1 { warnings.insert("重複ノートのPoly Pressureは元の値を保持しています。") }
            }
        }
        // Original/negative groups can converge when blended. Do not silently export stuck-note risks.
        let outputNotes = try out.notes()
        guard zip(notes, outputNotes).allSatisfy({ a, b in a.track == b.track && a.on == b.on && a.off == b.off && a.start == b.start && a.end == b.end && a.velocity == b.velocity && a.channel == b.channel }) else {
            throw MIDIError.invalid("Blendまたは音域の変更でノートが衝突しました。Blendを0% / 100%にするか、トラックを分けてください。元MIDIは変更されていません。")
        }
        let lanes = Dictionary(grouping: outputNotes, by: { "\($0.track):\($0.channel):\($0.pitch)" })
        for lane in lanes.values {
            let sorted = lane.sorted { $0.start < $1.start }
            var latestEnd = -1
            for n in sorted { if n.start < latestEnd { warnings.insert("同一音高の重なりがあります。音源によって発音が変わるため、DAWで確認してください。") }; latestEnd = max(latestEnd,n.end) }
        }
        if notes.contains(where: { $0.channel == 9 }) { warnings.insert("ドラム用MIDIチャンネル10は変換対象外です。") }
        if file.tracks.contains(where: { $0.events.contains { $0.bytes.first == 0xff && $0.bytes.dropFirst().first == 0x59 } }) { warnings.insert("元MIDIの調号メタ情報は保持しています。書き出し後の譜面の調号はDAWで確認してください。") }
        return ConversionResult(file:out,warnings:warnings.sorted())
    }
}
