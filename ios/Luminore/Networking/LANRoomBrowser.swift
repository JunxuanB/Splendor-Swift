@preconcurrency import Network
import Foundation
import LuminoreCore

struct DiscoveredLANRoom: Identifiable, Hashable {
    let descriptor: RoomDescriptor
    let endpoint: NWEndpoint

    var id: UUID { descriptor.id }
}

@MainActor
final class LANRoomBrowser: ObservableObject {
    @Published private(set) var rooms: [DiscoveredLANRoom] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.junxuanb.Luminore.lan-browser")

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: LANSessionService.serviceType, domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.isSearching = state == .ready || state == .setup || state == .waiting(.posix(.EINPROGRESS))
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let parsed = results.compactMap(Self.parse)
                .sorted { $0.descriptor.name.localizedStandardCompare($1.descriptor.name) == .orderedAscending }
            Task { @MainActor in self?.rooms = parsed }
        }
        self.browser = browser
        isSearching = true
        browser.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
        rooms = []
    }

    private nonisolated static func parse(_ result: NWBrowser.Result) -> DiscoveredLANRoom? {
        guard case let .bonjour(record) = result.metadata,
              let idText = record["id"], let id = UUID(uuidString: idText),
              let name = record["name"], let host = record["host"],
              let countText = record["count"], let count = Int(countText),
              let maximumText = record["max"], let maximum = Int(maximumText),
              let stageText = record["stage"], let stage = RoomStage(rawValue: stageText),
              record["pv"] == String(WireEnvelope.currentProtocolVersion)
        else { return nil }
        let descriptor = RoomDescriptor(
            id: id,
            name: name,
            hostNickname: host,
            playerCount: count,
            maximumPlayers: maximum,
            isPasswordProtected: record["locked"] == "1",
            stage: stage
        )
        return DiscoveredLANRoom(descriptor: descriptor, endpoint: result.endpoint)
    }
}
