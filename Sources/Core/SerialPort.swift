import Darwin
import Foundation

enum SerialError: LocalizedError {
    case openFailed(String, errno: Int32)
    case notOpen
    case configureFailed(String, errno: Int32)
    case writeFailed(errno: Int32)
    case baudRateRejected(Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let e):
            "Could not open \(path): \(String(cString: strerror(e)))"
        case .notOpen:
            "The port is not open."
        case .configureFailed(let what, let e):
            "Could not configure the port (\(what)): \(String(cString: strerror(e)))"
        case .writeFailed(let e):
            "Write failed: \(String(cString: strerror(e)))"
        case .baudRateRejected(let b):
            """
            The driver refused \(b) baud. On macOS this usually means Apple's built-in \
            CH340 driver is in use; install WCH's CH34xVCPDriver.
            """
        }
    }
}

/// A raw serial port.
///
/// The one subtlety that matters on macOS: this adapter runs at 2,000,000 baud, and
/// macOS termios has no standard constant above B230400. Rates above that must be
/// programmed with the `IOSSIOSPEED` ioctl *after* `tcsetattr`, or the chip keeps
/// whatever the last standard rate was.
///
/// Apple's own CH340 driver mis-programs the divisor at 2 Mbaud and delivers roughly
/// half that, with no error anywhere — the adapter simply never replies. WCH's
/// CH34xVCPDriver programs it correctly. See the README.
final class SerialPort: @unchecked Sendable {
    private var fd: Int32 = -1
    private var readThread: Thread?
    private let lock = NSLock()
    private var running = false

    /// `_IOW('T', 2, speed_t)`. `speed_t` is `unsigned long`, so 8 bytes on arm64.
    private static let iossiospeed64: UInt = 0x8008_5402
    /// Historical 4-byte form, still accepted by some drivers.
    private static let iossiospeed32: UInt = 0x8004_5402

    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return fd >= 0
    }

    // MARK: - Lifecycle

    func open(
        path: String,
        baud: Int,
        stopBits: Int = 2,
        onBytes: @escaping @Sendable ([UInt8]) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard fd < 0 else { return }

        let handle = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard handle >= 0 else { throw SerialError.openFailed(path, errno: errno) }

        // Take exclusive use so a stray process cannot interleave with us.
        _ = ioctl(handle, TIOCEXCL)

        // Clear O_NONBLOCK now that the port is open; reads are paced with poll().
        _ = fcntl(handle, F_SETFL, 0)

        var opts = termios()
        guard tcgetattr(handle, &opts) == 0 else {
            let e = errno; Darwin.close(handle)
            throw SerialError.configureFailed("tcgetattr", errno: e)
        }

        cfmakeraw(&opts)
        opts.c_cflag |= tcflag_t(CREAD | CLOCAL)
        opts.c_cflag &= ~tcflag_t(CSIZE)
        opts.c_cflag |= tcflag_t(CS8)
        opts.c_cflag &= ~tcflag_t(PARENB)
        opts.c_cflag &= ~tcflag_t(CRTSCTS)
        if stopBits == 2 {
            opts.c_cflag |= tcflag_t(CSTOPB)
        } else {
            opts.c_cflag &= ~tcflag_t(CSTOPB)
        }
        opts.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)

        // Non-blocking semantics: return whatever is available.
        withUnsafeMutablePointer(to: &opts.c_cc) {
            $0.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
        }

        // Seed a standard rate; IOSSIOSPEED below sets the real one.
        let seed = speed_t(min(baud, 115_200))
        cfsetispeed(&opts, seed)
        cfsetospeed(&opts, seed)

        guard tcsetattr(handle, TCSANOW, &opts) == 0 else {
            let e = errno; Darwin.close(handle)
            throw SerialError.configureFailed("tcsetattr", errno: e)
        }

        // The actual rate. Required for anything above B230400.
        var speed = speed_t(baud)
        if ioctl(handle, Self.iossiospeed64, &speed) == -1 {
            var speed32 = UInt32(baud)
            if ioctl(handle, Self.iossiospeed32, &speed32) == -1 {
                let e = errno
                Darwin.close(handle)
                _ = e
                throw SerialError.baudRateRejected(baud)
            }
        }

        _ = tcflush(handle, TCIOFLUSH)
        fd = handle
        running = true
        startReading(onBytes: onBytes)
    }

    func close() {
        lock.lock()
        running = false
        let handle = fd
        fd = -1
        lock.unlock()

        readThread?.cancel()
        readThread = nil
        if handle >= 0 {
            _ = tcflush(handle, TCIOFLUSH)
            Darwin.close(handle)
        }
    }

    // MARK: - I/O

    func write(_ bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { throw SerialError.notOpen }
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBufferPointer {
                Darwin.write(fd, $0.baseAddress!, $0.count)
            }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw SerialError.writeFailed(errno: errno)
            }
            offset += n
        }
        _ = tcdrain(fd)
    }

    func flushIO() {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return }
        _ = tcflush(fd, TCIOFLUSH)
    }

    private func startReading(onBytes: @escaping @Sendable ([UInt8]) -> Void) {
        let thread = Thread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while let self, self.running {
                self.lock.lock()
                let handle = self.fd
                self.lock.unlock()
                guard handle >= 0 else { break }

                var pfd = pollfd(fd: handle, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pfd, 1, 50)          // 50 ms tick
                if ready <= 0 { continue }

                let n = buf.withUnsafeMutableBufferPointer {
                    Darwin.read(handle, $0.baseAddress!, $0.count)
                }
                if n > 0 {
                    onBytes(Array(buf[0..<n]))
                } else if n < 0 && errno != EAGAIN && errno != EINTR {
                    break
                }
            }
        }
        thread.name = "USBCAN.serial.read"
        thread.qualityOfService = .userInitiated
        readThread = thread
        thread.start()
    }

    deinit { close() }
}
