import Foundation

/// Passthrough wrapper retained only so the `determineBasal` call sites keep
/// their labeled structure. The former sub-section timing/logging (the
/// `[ALGOPERF-SUB]` lines and per-loop collector accumulation) was removed
/// along with the JS/Swift comparison tooling; this simply runs the work.
enum OrefSubTimer {
    @inline(__always) static func time<T>(_: String, _ work: () throws -> T) rethrows -> T {
        try work()
    }
}
