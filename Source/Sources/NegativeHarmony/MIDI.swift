import Foundation

enum MIDIError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}
struct MIDIEvent: Equatable {
    var tick: Int
    var bytes: [UInt8]
}
struct MIDINote: Identifiable, Equatable {
    var id: Int
    var track: Int
    var on: Int
    var off: Int
    var start: Int
    var end: Int
    var pitch: Int
    var velocity: Int
    var channel: Int
}
struct MIDITrack {
    var events: [MIDIEvent]
    var name: String {
        for e in events where e.bytes.count > 2 && e.bytes[0] == 0xff && e.bytes[1] == 3 {
            var r = ByteReader(bytes: Array(e.bytes.dropFirst(2)))
            if let n = try? r.vlq(), let b = try? r.take(n) { return String(bytes: b, encoding: .utf8) ?? "MIDI Track" }
        }
        return "Track"
    }
}
struct ByteReader {
    var bytes: [UInt8]
    var position = 0
    var remaining: Int { bytes.count - position }
    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw MIDIError.invalid("MIDIデータが途中で切れています。") }
        defer { position += 1 }; return bytes[position]
    }
    mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, n <= remaining else { throw MIDIError.invalid("MIDIイベントの長さが不正です。") }
        defer { position += n }; return Array(bytes[position..<position+n])
    }
    mutating func integer(_ n: Int) throws -> Int { try take(n).reduce(0) { ($0 << 8) | Int($1) } }
    mutating func vlq() throws -> Int {
        var v = 0
        for _ in 0..<4 { let b = try byte(); v = (v << 7) | Int(b & 127); if b < 128 { return v } }
        throw MIDIError.invalid("MIDIの可変長数値が不正です。")
    }
}
func vlq(_ n: Int) -> [UInt8] {
    var v = n; var b = [UInt8(v & 127)]; v >>= 7
    while v > 0 { b.insert(UInt8(v & 127) | 128, at: 0); v >>= 7 }; return b
}
func bigEndian(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).reversed().map { UInt8((v >> ($0 * 8)) & 255) } }
struct MIDIFile {
    var format: Int
    var division: Int
    var tracks: [MIDITrack]
    init(format: Int = 1, division: Int = 480, tracks: [MIDITrack]) { self.format = format; self.division = division; self.tracks = tracks }
    init(data: Data) throws {
        guard data.count <= 20_000_000 else { throw MIDIError.invalid("MVPでは20 MB以下のMIDIに対応しています。") }
        var r = ByteReader(bytes: Array(data))
        guard try r.take(4) == Array("MThd".utf8) else { throw MIDIError.invalid("標準MIDIファイル（.mid / .midi）を選んでください。") }
        let length = try r.integer(4)
        guard length >= 6 else { throw MIDIError.invalid("MIDIヘッダーが不正です。") }
        format = try r.integer(2); let count = try r.integer(2); division = try r.integer(2)
        guard format == 0 || format == 1, count > 0, format != 0 || count == 1 else { throw MIDIError.invalid("SMF Format 0 / 1に対応しています。Format 2は未対応です。") }
        guard division > 0 && division < 0x8000 else { throw MIDIError.invalid("PPQ形式のMIDIが必要です。SMPTE形式は未対応です。") }
        _ = try r.take(length - 6); tracks = []
        for _ in 0..<count {
            guard try r.take(4) == Array("MTrk".utf8) else { throw MIDIError.invalid("MIDIトラックが不正です。") }
            let size = try r.integer(4); var t = ByteReader(bytes: try r.take(size))
            var tick = 0; var running: UInt8 = 0; var events: [MIDIEvent] = []
            while t.remaining > 0 {
                tick += try t.vlq(); var s = try t.byte()
                if s < 128 { guard running >= 0x80 else { throw MIDIError.invalid("Running Statusが不正です。") }; t.position -= 1; s = running }
                var b: [UInt8] = [s]
                if s == 0xff {
                    let kind = try t.byte(); let n = try t.vlq(); b += [kind] + vlq(n) + (try t.take(n)); running = 0
                } else if s == 0xf0 || s == 0xf7 {
                    let n = try t.vlq(); b += vlq(n) + (try t.take(n)); running = 0
                } else if s >= 0x80 && s < 0xf0 {
                    running = s; let n = (s & 0xf0 == 0xc0 || s & 0xf0 == 0xd0) ? 1 : 2
                    let payload = try t.take(n)
                    guard payload.allSatisfy({ $0 < 128 }) else { throw MIDIError.invalid("MIDIチャンネルデータが不正です。") }
                    b += payload
                } else { throw MIDIError.invalid("未対応のMIDIステータスです。") }
                events.append(MIDIEvent(tick: tick, bytes: b))
            }
            tracks.append(MIDITrack(events: events))
        }
        _ = try notes()
    }
    func notes() throws -> [MIDINote] {
        var notes: [MIDINote] = []; var id = 0
        for (ti, t) in tracks.enumerated() {
            var active: [Int: [Int]] = [:]
            for (ei, e) in t.events.enumerated() where e.bytes.count >= 3 && e.bytes[0] < 0xf0 {
                let type = e.bytes[0] & 0xf0, ch = Int(e.bytes[0] & 15), p = Int(e.bytes[1]), key = ch * 128 + p
                if type == 0x90 && e.bytes[2] > 0 { active[key, default: []].append(ei) }
                else if type == 0x80 || (type == 0x90 && e.bytes[2] == 0) {
                    guard var queue = active[key], !queue.isEmpty else { throw MIDIError.invalid("対応するNote OnのないNote Offがあります（Track \(ti+1)）。") }
                    let on = queue.removeFirst(); active[key] = queue
                    let first = t.events[on]
                    notes.append(MIDINote(id: id, track: ti, on: on, off: ei, start: first.tick, end: e.tick, pitch: p, velocity: Int(first.bytes[2]), channel: ch)); id += 1
                }
            }
            guard active.values.allSatisfy({ $0.isEmpty }) else { throw MIDIError.invalid("Note Offのないノートがあります（Track \(ti+1)）。DAWから再書き出ししてください。") }
        }
        return notes.sorted { ($0.start, $0.track, $0.on) < ($1.start, $1.track, $1.on) }
    }
    func data() -> Data {
        var b = Array("MThd".utf8) + bigEndian(6, 4) + bigEndian(format, 2) + bigEndian(tracks.count, 2) + bigEndian(division, 2)
        for t in tracks {
            var payload: [UInt8] = []; var previous = 0
            for e in t.events { payload += vlq(e.tick - previous) + e.bytes; previous = e.tick }
            if t.events.last?.bytes.prefix(2) != [0xff, 0x2f] { payload += [0, 0xff, 0x2f, 0] }
            b += Array("MTrk".utf8) + bigEndian(payload.count, 4) + payload
        }
        return Data(b)
    }
    static func demo() -> MIDIFile {
        func track(_ name: String, _ chords: [[Int]], channel: UInt8) -> MIDITrack {
            var e = [MIDIEvent(tick: 0, bytes: [0xff,3] + vlq(name.utf8.count) + Array(name.utf8))]
            for (i, pitches) in chords.enumerated() {
                for p in pitches { e.append(MIDIEvent(tick:i*1920, bytes:[0x90|channel,UInt8(p),88])) }
                for p in pitches { e.append(MIDIEvent(tick:i*1920+1680, bytes:[0x80|channel,UInt8(p),64])) }
            }
            e.append(MIDIEvent(tick:7680,bytes:[0xff,0x2f,0])); return MIDITrack(events:e)
        }
        let tempo = MIDITrack(events: [MIDIEvent(tick:0, bytes:[0xff,0x51,3,7,0xa1,0x20]), MIDIEvent(tick:0,bytes:[0xff,0x58,4,4,2,24,8]), MIDIEvent(tick:7680,bytes:[0xff,0x2f,0])])
        return MIDIFile(tracks:[tempo,track("Melody",[[72],[79],[74],[76]],channel:0),track("Chords",[[48,52,55],[45,48,52],[41,45,48],[43,47,50,53]],channel:1)])
    }
}
