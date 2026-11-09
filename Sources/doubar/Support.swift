import Foundation

func log(_ message: String) {
    FileHandle.standardError.write(Data("[doubar] \(message)\n".utf8))
}

/// Run an executable and return its stdout, off the main thread.
func run(_ path: String, _ args: [String]) async -> String? {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch {
                cont.resume(returning: nil)
                return
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            cont.resume(returning: p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
        }
    }
}

struct ShellResult {
    var stdout: String
    var stderr: String
    /// Nil when the command couldn't start or was killed for taking too long.
    var status: Int32?
}

/// Run `command` with `/bin/zsh -c`, off the main thread. A GUI app's PATH
/// lacks Homebrew's, so it's added. Killed after `timeout` seconds.
func runShell(_ command: String, timeout: TimeInterval = 20) async -> ShellResult {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", command]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch {
                cont.resume(returning: ShellResult(stdout: "", stderr: "\(error.localizedDescription)", status: nil))
                return
            }
            var timedOut = false
            let kill = DispatchWorkItem { timedOut = true; p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
            // stderr is drained on its own thread so a chatty command can't fill the pipe.
            var errData = Data()
            let errDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                errData = err.fileHandleForReading.readDataToEndOfFile()
                errDone.signal()
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            kill.cancel()
            errDone.wait()
            cont.resume(returning: ShellResult(
                stdout: String(decoding: data, as: UTF8.self),
                stderr: timedOut ? "timed out after \(Int(timeout)) s" : String(decoding: errData, as: UTF8.self),
                status: timedOut ? nil : p.terminationStatus))
        }
    }
}

enum SingleInstance {
    private static var fd: Int32 = -1

    /// Hold an exclusive lock for the life of the process. The kernel drops
    /// it when we exit, so a crash never leaves a stale lock behind.
    static func acquire() -> Bool {
        let path = NSTemporaryDirectory() + "doubar.lock"
        fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }
        return flock(fd, LOCK_EX | LOCK_NB) == 0
    }
}

/// Events from `doubar emit`, carried over distributed notifications.
enum IPC {
    static let notification = Notification.Name("com.yaofur.doubar.event")

    static func emit(_ args: [String]) -> Int32 {
        guard let name = args.first, !name.isEmpty else {
            log("emit: missing event name")
            return 64
        }
        var params: [String: String] = [:]
        for arg in args.dropFirst() {
            guard let (k, v) = arg.split(separator: "=", maxSplits: 1).pair else {
                log("emit: skipping arg '\(arg)' (expected key=value)")
                continue
            }
            params[k.trimmingCharacters(in: CharacterSet(charactersIn: "-"))] = v
        }
        var info: [String: Any] = ["event": name]
        if !params.isEmpty { info["params"] = params }
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: nil, userInfo: info, deliverImmediately: true)
        return 0
    }

    /// Call `handler` with each emitted event name and its parameters.
    static func listen(_ handler: @escaping (String, [String: String]) -> Void) {
        observeDistributed(notification) { note in
            guard let event = note.userInfo?["event"] as? String else { return }
            handler(event, note.userInfo?["params"] as? [String: String] ?? [:])
        }
    }
}

/// Observe a distributed notification on the main queue. Delivery must be
/// immediate: a Cocoa app suspends distributed notifications while it is
/// inactive, and the bar is never active.
func observeDistributed(_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
    let observer = DistributedObserver(handler)
    DistributedObserver.retained.append(observer)
    DistributedNotificationCenter.default().addObserver(
        observer, selector: #selector(DistributedObserver.receive(_:)),
        name: name, object: nil, suspensionBehavior: .deliverImmediately)
}

private final class DistributedObserver: NSObject {
    static var retained: [DistributedObserver] = []
    let handler: (Notification) -> Void
    init(_ handler: @escaping (Notification) -> Void) { self.handler = handler }

    @objc func receive(_ note: Notification) {
        DispatchQueue.main.async { self.handler(note) }
    }
}

private extension Array where Element == Substring {
    var pair: (String, String)? {
        count == 2 && !self[0].isEmpty ? (String(self[0]), String(self[1])) : nil
    }
}
