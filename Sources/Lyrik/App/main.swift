import AppKit

// Diagnostics: `Lyrik --lyrics-test "<title>" "<artist>" <seconds> [album]`
// looks a song up and prints what the lyric sources returned, then exits.
if CommandLine.arguments.count >= 5, CommandLine.arguments[1] == "--lyrics-test" {
    let args = CommandLine.arguments
    let title = args[2], artist = args[3], duration = Double(args[4]) ?? 0
    let album = args.count > 5 ? args[5] : ""
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        let result = await LyricsProvider.shared.lookup(title: title, artist: artist, album: album, duration: duration)
        switch result {
        case .found(let l):
            print("found: \(l.source), \(l.lines.count) lines, wordLevel=\(l.wordLevel), gap=\(l.lengthGap)")
            for line in l.lines.prefix(8) {
                let words = line.words.map { String(format: "%@@%.2f", $0.display, $0.start) }.joined(separator: " ")
                print(String(format: "[%6.2f–%6.2f] %@", line.start, line.end, line.text))
                print("           \(words)")
            }
            let frame = LyricFrame.make(lines: l.lines, time: (l.lines.dropFirst(3).first?.start ?? 0) + 0.4)
            print("frame@line4+0.4s: index=\(frame.index ?? -1) word=\(frame.wordIndex ?? -1) progress=\(String(format: "%.2f", frame.wordProgress))")
        case .instrumental: print("instrumental")
        case .untimed: print("untimed")
        case .otherLength(let g): print("otherLength \(g)")
        case .notFound: print("notFound")
        case .unreachable: print("unreachable")
        }
        print("symbol(rain)=\(WordVisualResolver.shared.symbol(for: "rain") ?? "nil") symbol(heart)=\(WordVisualResolver.shared.symbol(for: "Heart,") ?? "nil") symbol(ocean)=\(WordVisualResolver.shared.symbol(for: "ocean") ?? "nil") symbol(guitar)=\(WordVisualResolver.shared.symbol(for: "guitar") ?? "nil") symbol(the)=\(WordVisualResolver.shared.symbol(for: "the") ?? "nil")")
        done.signal()
    }
    done.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
