import SwiftUI
import AppKit

@main struct NegativeHarmonyApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Negative Harmony MIDI Converter") {
            ContentView(model:model)
                .onOpenURL { model.load($0) }
                .onAppear {
                    NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true)
                    if let i = CommandLine.arguments.firstIndex(of:"--smoke-test"), i+1 < CommandLine.arguments.count {
                        let path = CommandLine.arguments[i+1]
                        let fixtureURL = URL(fileURLWithPath:path).appendingPathComponent("Drop-Test.mid")
                        try? MIDIFile.demo().data().write(to:fixtureURL)
                        let provider = NSItemProvider(contentsOf:fixtureURL)!
                        let accepted = model.drop([provider])
                        DispatchQueue.main.asyncAfter(deadline:.now()+3) {
                            model.play("Negative")
                            DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                                var report: [String:Any] = ["dropAccepted":accepted,"loadedViaDrop":model.sourceName == "Drop-Test","sourceNotes":model.originalNotes.count,"negativeNotes":model.negativeNotes.count,"playback":model.playback,"playerIsPlaying":model.isPlaying,"positionSeconds":model.playPosition,"exportExists":model.exportURL.map { FileManager.default.fileExists(atPath:$0.path) } ?? false,"error":model.error ?? ""]
                                if let w = NSApp.windows.first(where: { $0.isVisible }), let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                                    view.cacheDisplay(in:view.bounds,to:rep)
                                    if let data = rep.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path).appendingPathComponent("app-preview.png")); report["windowWidth"] = view.bounds.width }
                                }
                                if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:path).appendingPathComponent("gui-smoke.json")) }
                                model.stop()
                            }
                        }
                    }
                }
        }.defaultSize(width:1180,height:850)
        .commands {
            CommandGroup(replacing:.newItem) { Button("MIDIを開く…") { model.openPanel() }.keyboardShortcut("o"); Button("MIDIを書き出す…") { model.export() }.keyboardShortcut("s").disabled(model.result == nil) }
        }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false
    private let teal = Color(red:0.24,green:0.88,blue:0.75)
    var body: some View {
        VStack(spacing:0) {
            header
            ScrollView {
                VStack(spacing:18) {
                    inputCard
                    HStack(alignment:.top,spacing:18) { settingsCard.frame(width:330); comparisonCard }
                    trackCard
                }.padding(24)
            }
            footer
        }
        .frame(minWidth:1030,minHeight:760)
        .background(Color(red:0.055,green:0.075,blue:0.11))
        .preferredColorScheme(.dark)
        .onChange(of:model.settings) { _ in model.scheduleConversion() }
        .onChange(of:model.roles) { _ in model.scheduleConversion() }
        .alert("確認してください",isPresented:Binding(get:{model.error != nil},set:{ if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var header: some View {
        HStack(spacing:16) {
            Image(systemName:"arrow.triangle.swap").font(.system(size:32,weight:.bold)).foregroundStyle(teal).frame(width:62,height:62).background(teal.opacity(0.12),in:RoundedRectangle(cornerRadius:18))
            VStack(alignment:.leading,spacing:5) { Text("NEGATIVE HARMONY").font(.system(size:26,weight:.bold,design:.rounded)); Text("MIDI CONVERTER  /  音の向こう側へ").font(.system(size:12,weight:.medium)).foregroundStyle(.secondary).tracking(2) }
            Spacer(); Text("NATIVE MIDI STUDIO").font(.caption.weight(.semibold)).foregroundStyle(teal)
        }.padding(.horizontal,28).padding(.vertical,20).background(.white.opacity(0.025))
    }
    private var inputCard: some View {
        HStack(spacing:22) {
            Image(systemName:"square.and.arrow.down").font(.system(size:40,weight:.light)).foregroundStyle(teal).frame(width:65)
            VStack(alignment:.leading,spacing:7) {
                Text(model.sourceName).font(.title3.weight(.semibold)).lineLimit(1)
                Text(model.source == nil ? "ここにMIDIをドラッグ＆ドロップ（.mid / .midi）" : "\(model.originalNotes.count) notes · \(model.source?.tracks.count ?? 0) tracks · \(model.source?.division ?? 480) PPQ").foregroundStyle(.secondary)
                Text("メロディとコードを含む1つのMIDIに対応。下でトラックの役割を選べます。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.demo() } label: { Label("デモ",systemImage:"sparkles").padding(10) }.buttonStyle(.bordered)
            Button { model.openPanel() } label: { Label("MIDIを開く",systemImage:"folder").font(.headline).padding(12) }.buttonStyle(.borderedProminent).tint(teal).foregroundStyle(.black)
        }.padding(22).background(targeted ? teal.opacity(0.17) : .white.opacity(0.04),in:RoundedRectangle(cornerRadius:20))
        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(teal.opacity(targeted ? 0.9 : 0.25),style:StrokeStyle(lineWidth:1.5,dash:[7,5])))
        .onDrop(of:[UTType.fileURL.identifier],isTargeted:$targeted,perform:model.drop)
    }
    private var settingsCard: some View {
        VStack(alignment:.leading,spacing:15) {
            Label("変換設定",systemImage:"slider.horizontal.3").font(.title3.weight(.bold))
            HStack { Picker("Key",selection:$model.settings.tonic) { ForEach(0..<12) { Text(pitchNames[$0]).tag($0) } }; Picker("Mode",selection:$model.settings.minor) { Text("Major").tag(false); Text("Minor").tag(true) }.labelsHidden() }
            Picker("Axis",selection:$model.settings.axis) { ForEach(AxisMode.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
            if model.settings.axis == .custom { Picker("Cの変換先",selection:$model.settings.customSum) { ForEach(0..<12) { Text(pitchNames[$0]).tag($0) } } }
            Text(model.settings.axis == .custom ? "反転式：p′ = \(model.settings.sum) − p (mod 12)" : "Classic / Tonic–Dominant：主音 ↔ 属音\nMajor / Minorとも同じ主音基準の反転です。") .font(.caption).foregroundStyle(.secondary)
            Picker("変換対象",selection:$model.settings.scope) { ForEach(ConversionScope.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
            Divider()
            Toggle("転回形を維持",isOn:$model.settings.preserveInversion)
            Toggle("オクターブ自動最適化",isOn:$model.settings.autoOctave)
            Toggle("Voice Leading 最適化",isOn:$model.settings.voiceLeading)
            Text("転回形：認識できる同時発音コードの転回次数を維持。Voice Leading：前の響きとの移動を抑制。").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack { Text("Harmony Blend").fontWeight(.semibold); Spacer(); Text("\(Int(model.settings.blend))%").monospacedDigit().foregroundStyle(teal) }
            Slider(value:$model.settings.blend,in:0...100).tint(teal).accessibilityLabel("Harmony Blend")
            HStack { Text("Original"); Spacer(); Text("Negative") }.font(.caption).foregroundStyle(.secondary)
            Text("同時発音グループ単位で原音と反転音を配分します。音量とベロシティは保持します。").font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:18))
    }
    private var comparisonCard: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack { Label("Original / Negative",systemImage:"pianokeys").font(.title3.weight(.bold)); Spacer(); if model.isBusy { ProgressView().controlSize(.small) } }
            HStack(spacing:6) {
                ForEach(0..<12) { i in VStack(spacing:5) { Text(pitchNames[i]).foregroundStyle(.secondary); Text("↓").foregroundStyle(.tertiary); Text(pitchNames[pc(model.settings.sum-i)]).foregroundStyle(teal) }.font(.system(size:11,weight:.medium)).frame(maxWidth:.infinity) }
            }.padding(12).background(.black.opacity(0.18),in:RoundedRectangle(cornerRadius:12))
            PianoRoll(original:model.originalNotes,negative:model.result == nil ? [] : model.negativeNotes, division:model.source?.division ?? 480).frame(height:190).accessibilityLabel("OriginalとNegativeのピアノロール比較")
            HStack(spacing:16) { Label("Original",systemImage:"circle.fill").foregroundStyle(Color.orange); Label("Negative / Blend",systemImage:"circle.fill").foregroundStyle(teal); Spacer(); Text("先頭32拍を表示").foregroundStyle(.secondary) }.font(.caption)
            Divider()
            Text("コード比較").font(.headline)
            chordRows
        }.padding(20).frame(maxWidth:.infinity,alignment:.topLeading).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:18))
    }
    private var chordRows: some View {
        let rows = chordComparisons()
        return VStack(spacing:7) {
            if rows.isEmpty { Text("コードトラックを読み込むと構成音から解析します。").foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            ForEach(Array(rows.enumerated()),id:\.offset) { _,r in
                HStack { Text(r.0).foregroundStyle(.secondary).frame(width:74,alignment:.leading); Text(r.1).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading); Image(systemName:"arrow.right").foregroundStyle(.secondary); Text(r.2).foregroundStyle(teal).frame(maxWidth:.infinity,alignment:.leading) }.font(.system(size:13,weight:.medium,design:.rounded))
            }
            Text("厳密一致で認識。曖昧・未登録の和音は構成音を表示（先頭8箇所）。").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func chordComparisons() -> [(String,String,String)] {
        let notes = model.originalNotes.filter { model.roles[$0.track] == .chords && $0.channel != 9 }
        let ticks = Set(notes.map(\.start)).sorted().prefix(8)
        return ticks.map { tick in
            let old = notes.filter { $0.start <= tick && $0.end > tick }.map(\.pitch)
            let new = model.negativeNotes.filter { model.roles[$0.track] == .chords && $0.channel != 9 && $0.start <= tick && $0.end > tick }.map(\.pitch)
            let beat = Double(tick) / Double(model.source?.division ?? 480) + 1
            return (String(format:"拍 %.1f",beat),ChordAnalyzer.label(old),model.result == nil ? "—" : ChordAnalyzer.label(new))
        }
    }
    private var trackCard: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("トラックの役割",systemImage:"square.stack.3d.up").font(.headline)
            if let source = model.source {
                ForEach(source.tracks.indices,id:\.self) { i in
                    let notes = model.originalNotes.filter { $0.track == i }
                    if !notes.isEmpty {
                        HStack { Image(systemName:model.roles[i] == .chords ? "pianokeys" : "music.note").font(.title2).foregroundStyle(teal).frame(width:32); Text("\(i+1). \(source.tracks[i].name)").frame(maxWidth:.infinity,alignment:.leading); Text("\(notes.count) notes").foregroundStyle(.secondary); Picker("役割",selection:Binding(get:{model.roles[i] ?? .melody},set:{model.roles[i] = $0})) { ForEach(TrackRole.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.frame(width:200) }
                    }
                }
            } else { Text("読み込み後に自動判定します。必要に応じてメロディ／コードを変更してください。").foregroundStyle(.secondary) }
            ForEach(model.warnings,id:\.self) { Text("• " + $0).font(.caption).foregroundStyle(.yellow) }
            Text("MIDIチャンネル10（ドラム）は保持。メロディと伴奏が同じトラックの場合は、DAWで分離してから読み込んでください。").font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:18))
    }
    private var footer: some View {
        HStack(spacing:12) {
            Button { model.play("Original") } label: { Label("Original",systemImage:"play.circle.fill").font(.headline).padding(10) }.disabled(model.result == nil)
            Button { model.play("Negative") } label: { Label("Negative",systemImage:"play.circle.fill").font(.headline).padding(10) }.disabled(model.result == nil)
            Button { model.play("比較") } label: { Label("比較再生",systemImage:"arrow.left.arrow.right.circle.fill").font(.headline).padding(10) }.disabled(model.result == nil)
            Button { model.stop() } label: { Image(systemName:"stop.fill").font(.title2).padding(8) }.help("再生を停止")
            VStack(alignment:.leading,spacing:3) { Text(model.playback).font(.caption); Text("内蔵GM音源 · 比較は順番に再生").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
            if let url = model.exportURL {
                Label("Logicへドラッグ",systemImage:"hand.draw.fill").font(.headline).padding(15).background(teal.opacity(0.13),in:RoundedRectangle(cornerRadius:12)).foregroundStyle(teal).onDrag { NSItemProvider(contentsOf:url)! }.help("FinderまたはLogic Proのソフトウェア音源トラックへドラッグ")
            }
            Button { model.export() } label: { Label("書き出し",systemImage:"square.and.arrow.up").font(.headline).padding(12) }.buttonStyle(.borderedProminent).tint(teal).foregroundStyle(.black).disabled(model.result == nil)
        }.buttonStyle(.bordered).padding(18).background(.black.opacity(0.2))
    }
}
import UniformTypeIdentifiers
struct PianoRoll: View {
    let original: [MIDINote]
    let negative: [MIDINote]
    let division: Int
    var body: some View {
        Canvas { context,size in
            let notes = original + negative
            let low = max(0,(notes.map(\.pitch).min() ?? 48)-3), high = min(127,(notes.map(\.pitch).max() ?? 84)+3)
            let total = max(1,high-low+1)
            // Preview spans a bounded number of ticks while fitting short demo files.
            let end = max(1,min(original.map(\.end).max() ?? division * 16,division * 32))
            for pitch in low...high {
                let y = size.height * Double(high-pitch) / Double(total)
                let rect = CGRect(x:0,y:y,width:size.width,height:size.height/Double(total))
                context.fill(Path(rect),with:.color([1,3,6,8,10].contains(pc(pitch)) ? .black.opacity(0.25) : .white.opacity(0.025)))
            }
            for beat in 0...16 {
                let x = size.width * Double(beat)/16
                var p = Path(); p.move(to:CGPoint(x:x,y:0)); p.addLine(to:CGPoint(x:x,y:size.height)); context.stroke(p,with:.color(.white.opacity(0.07)))
            }
            for (list,color,offset) in [(original,Color.orange,0.0),(negative,Color(red:0.24,green:0.88,blue:0.75),0.45)] {
                for n in list.prefix(12000) where n.start < end && n.channel != 9 {
                    let h = size.height/Double(total)
                    let rect = CGRect(x:size.width*Double(n.start)/Double(end),y:h*(Double(high-n.pitch)+offset),width:max(2,size.width*Double(min(end,n.end)-n.start)/Double(end)),height:max(1,h*0.5))
                    context.fill(Path(roundedRect:rect,cornerRadius:1),with:.color(color.opacity(0.85)))
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius:10)).overlay { if original.isEmpty { Text("MIDIを読み込むと、ここに音の反転が表示されます").font(.callout).foregroundStyle(.secondary) } }
    }
}
