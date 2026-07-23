@preconcurrency import Network
import Foundation
import LuminoreCore

final class LANPeerConnection: @unchecked Sendable {
    let connection: NWConnection
    var participantID: UUID?
    var challenge: AuthChallenge?

    private let queue: DispatchQueue
    private var framer = LengthPrefixedFramer()
    private var stopped = false
    private let onEnvelope: @Sendable (WireEnvelope, LANPeerConnection) -> Void
    private let onStop: @Sendable (LANPeerConnection, Error?) -> Void

    init(
        connection: NWConnection,
        label: String,
        onEnvelope: @escaping @Sendable (WireEnvelope, LANPeerConnection) -> Void,
        onStop: @escaping @Sendable (LANPeerConnection, Error?) -> Void
    ) {
        self.connection = connection
        queue = DispatchQueue(label: label)
        self.onEnvelope = onEnvelope
        self.onStop = onStop
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveNext()
            case let .failed(error):
                self.finish(error)
            case .cancelled:
                self.finish(nil)
            case let .waiting(error):
                // The endpoint is currently unreachable (host gone, stale Bonjour
                // result, network hiccup). NWConnection would otherwise sit here
                // indefinitely, so treat it as a drop: cancel and report, letting the
                // session's reconnect loop try again with a freshly resolved endpoint.
                self.connection.cancel()
                self.finish(error)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ envelope: WireEnvelope) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            do {
                let payload = try JSONEncoder.luminore.encode(envelope)
                let framed = try LengthPrefixedFramer.frame(payload)
                self.connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                    if let error { self?.finish(error) }
                })
            } catch {
                self.finish(error)
            }
        }
    }

    func cancel() {
        connection.cancel()
        finish(nil)
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            do {
                if let data, !data.isEmpty {
                    for frame in try self.framer.append(data) {
                        let envelope = try JSONDecoder.luminore.decode(WireEnvelope.self, from: frame)
                        self.onEnvelope(envelope, self)
                    }
                }
                if let error {
                    self.finish(error)
                } else if complete {
                    self.finish(nil)
                } else {
                    self.receiveNext()
                }
            } catch {
                self.finish(error)
            }
        }
    }

    private func finish(_ error: Error?) {
        guard !stopped else { return }
        stopped = true
        onStop(self, error)
    }
}

private extension JSONEncoder {
    static var luminore: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var luminore: JSONDecoder { JSONDecoder() }
}
