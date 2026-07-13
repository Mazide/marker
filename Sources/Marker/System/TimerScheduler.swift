import Foundation

final class TimerScheduler: Scheduling {
    private final class Token: SchedulerToken {
        let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }

    @discardableResult
    func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) -> SchedulerToken {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            action()
        }
        return Token(timer)
    }
}