import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    @Published var source: MIDIFile?
    @Published var result: MIDIFile?
    @Published var sourceName = "MIDIファイルを読み込んでください"
    @Published var settings = HarmonySettings()
    @Published var roles: [Int:TrackRole] = [:]
    @Published var originalNotes: [MIDINote] = []
    @Published var negativeNotes: [MIDINote] = []
    @Published var warnings: [String] = []
    @Published var error: String?
    @Published var playback = "停止中"
    @Published var exportURL: URL?
    @Published var isBusy = false
    private var player: AVMIDIPlayer?
    var isPlaying: Bool { player?.isPlaying ?? false }
    var playPosition: Double { player?.currentPosition ?? 0 }
    private var generation = UUID()
    private var conversionGeneration = UUID()
    private var fileGeneration = UUID()
    private var pendingConversion: DispatchWorkItem?
    private let cache = FileManager.default.temporaryDirectory.appendingPathComponent("NegativeHarmony-\(UUID().uuidString)",isDirectory:true)
    init() { try? FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true) }
    func openPanel() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension:"mid") ?? .data, UTType(filenameExtension:"midi") ?? .data]; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { load(url) }
    }
    func load(_ url: URL) {
        stop(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let f = try MIDIFile(data:Data(contentsOf:url,options:.mappedIfSafe)); try install(f,name:url.deletingPathExtension().lastPathComponent)
        } catch { self.error = error.localizedDescription }
    }
    func demo() { do { try install(.demo(),name:"Demo · C → Am → F → G7") } catch { self.error = error.localizedDescription } }
    private func install(_ f: MIDIFile,name: String) throws {
        let notes = try f.notes()
        guard !notes.isEmpty else { throw MIDIError.invalid("ノートを含むMIDIを選んでください。") }
        guard notes.count <= 50000 else { throw MIDIError.invalid("MVPでは50,000ノート以下のMIDIに対応しています。") }
        stop(); source = f; sourceName = name; originalNotes = notes; fileGeneration = UUID()
        roles = Dictionary(uniqueKeysWithValues:f.tracks.indices.map { i in (i,HarmonyEngine.inferredRole(notes.filter { $0.track == i })) })
        convert()
    }
    func scheduleConversion() {
        pendingConversion?.cancel(); conversionGeneration = UUID(); stop(); result = nil; exportURL = nil; isBusy = source != nil
        let item = DispatchWorkItem { [weak self] in self?.convert() }; pendingConversion = item
        DispatchQueue.main.asyncAfter(deadline:.now()+0.18,execute:item)
    }
    func convert() {
        guard let source else { return }; stop(); result = nil; exportURL = nil; isBusy = true
        let settings = self.settings, roles = self.roles, token = UUID(), fileToken = fileGeneration
        conversionGeneration = token
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let converted = Result { try HarmonyEngine.convert(source,settings:settings,roles:roles) }
            DispatchQueue.main.async {
                guard let self, self.conversionGeneration == token, self.fileGeneration == fileToken else { return }
                self.isBusy = false
                do {
                    let r = try converted.get(); self.result = r.file; self.negativeNotes = try r.file.notes(); self.warnings = r.warnings
                    let url = self.cache.appendingPathComponent("Negative-\(UUID().uuidString.prefix(8)).mid")
                    try r.file.data().write(to:url,options:.atomic); self.exportURL = url
                } catch { self.result = nil; self.exportURL = nil; self.error = error.localizedDescription }
            }
        }
    }
    func stop() { generation = UUID(); player?.stop(); player = nil; playback = "停止中" }
    func play(_ kind: String) {
        stop(); guard let source, let result else { return }
        let token = UUID(); generation = token
        do {
            try start(kind == "Negative" ? result : source, label:kind == "比較" ? "Original → Negative：Original再生中" : "\(kind) 再生中",token:token) { [weak self] in
                guard let self, self.generation == token else { return }
                if kind == "比較" {
                    do { try self.start(result,label:"Original → Negative：Negative再生中",token:token) { [weak self] in self?.stop() } }
                    catch { self.error = error.localizedDescription; self.stop() }
                } else { self.stop() }
            }
        } catch { self.error = "再生できませんでした：\(error.localizedDescription)"; stop() }
    }
    private func start(_ file: MIDIFile,label: String,token: UUID,completion: @escaping () -> Void) throws {
        let bank = URL(fileURLWithPath:"/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        let p = try AVMIDIPlayer(data:file.data(),soundBankURL:FileManager.default.fileExists(atPath:bank.path) ? bank : nil)
        p.prepareToPlay(); player = p; playback = label
        p.play { DispatchQueue.main.async { [weak self] in guard self?.generation == token else { return }; completion() } }
    }
    func export() {
        guard let result else { return }
        let p = NSSavePanel(); p.allowedContentTypes = [UTType(filenameExtension:"mid") ?? .data]; p.nameFieldStringValue = "Negative Harmony.mid"
        if p.runModal() == .OK, let url = p.url {
            do { try result.data().write(to:url,options:.atomic) } catch { self.error = error.localizedDescription }
        }
    }
    func drop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else { error = "一度に1つのMIDIをドロップしてください。メロディとコードは別トラックで1つのMIDIにまとめられます。"; return false }
        provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { [weak self] item, error in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation:data,relativeTo:nil) }
            else { url = item as? URL }
            DispatchQueue.main.async { if let url { self?.load(url) } else { self?.error = error?.localizedDescription ?? "ファイルを読み込めませんでした。FinderからMIDIをドロップしてください。" } }
        }; return true
    }
}
