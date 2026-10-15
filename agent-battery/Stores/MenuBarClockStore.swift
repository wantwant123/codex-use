import AppKit
import Combine
import Foundation

final class MenuBarClockStore: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?
    private var wakeSubscription: AnyCancellable?

    init() {
        schedule()
        wakeSubscription = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.schedule() }
    }

    deinit { timer?.invalidate() }

    private func schedule() {
        now = Date()
        timer?.invalidate()
        let nextMinute = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
