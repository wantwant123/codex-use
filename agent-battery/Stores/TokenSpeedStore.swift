import Combine
import Foundation

final class TokenSpeedStore: ObservableObject {
    @Published private(set) var sample: TokenSpeedSample?

    private let settings: AppSettings
    private let reader = CodexTokenSpeedReader()
    private let queue = DispatchQueue(label: "agent-battery.token-speed", qos: .utility)
    private var timer: Timer?
    private var reading = false

    init(settings: AppSettings) {
        self.settings = settings
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    deinit { timer?.invalidate() }

    var text: String {
        guard let sample else { return "-- tok/s" }
        return String(format: "≈%.1f tok/s", sample.tokensPerSecond)
    }

    var menuBarText: String {
        guard sample != nil else { return text }
        return String(format: NSLocalizedString("tokenSpeed.recentValue", comment: ""), text)
    }

    private func refresh() {
        guard !reading else { return }
        reading = true
        let path = settings.codexSessionsPath
        let reader = reader
        queue.async { [weak self] in
            let value = try? reader.read(path: path)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.sample != value { self.sample = value }
                self.reading = false
            }
        }
    }
}
