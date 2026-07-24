import Foundation
import LuminoreCore
import SwiftData

struct MatchOutcomeRecordingResult: Equatable {
    let insertedHistory: Bool
    let insertedMedals: Int
}

/// Persists only the local profile's view of a finished match. The final snapshot
/// is authoritative for all three transports, so this recorder stays independent
/// of LAN, Internet, and MultipeerConnectivity details.
@MainActor
enum MatchOutcomeRecorder {
    static func record(
        snapshot: ClientGameSnapshot,
        ownerKey: String,
        localParticipantID: UUID,
        transport: MultiplayerMode,
        roomName: String = "",
        context: ModelContext
    ) throws -> MatchOutcomeRecordingResult {
        guard snapshot.status == .finished,
              let result = snapshot.result,
              snapshot.players.contains(where: { $0.id == localParticipantID })
        else {
            return MatchOutcomeRecordingResult(insertedHistory: false, insertedMedals: 0)
        }

        let normalizedRoomName = String(
            roomName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
        )
        var didUpdateMetadata = false

        let histories = try context.fetch(
            FetchDescriptor<CompletedGameRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
        )
        let historyKey = CompletedGameRecord.makeLogicalKey(ownerKey: ownerKey, gameID: snapshot.gameID)
        let insertedHistory: Bool
        if let history = histories.first(where: { $0.logicalKey == historyKey }) {
            if history.roomName.isEmpty, !normalizedRoomName.isEmpty {
                history.roomName = normalizedRoomName
                didUpdateMetadata = true
            }
            insertedHistory = false
        } else {
            context.insert(CompletedGameRecord(
                ownerKey: ownerKey,
                gameID: snapshot.gameID,
                localParticipantID: localParticipantID,
                roomName: normalizedRoomName,
                modeRawValue: snapshot.configuration.mode.rawValue,
                transportRawValue: transport.rawValue,
                endedAt: result.finishedAt,
                resultPayload: try JSONEncoder().encode(result)
            ))
            insertedHistory = true
        }

        var insertedMedals = 0
        if result.winnerIDs.contains(localParticipantID),
           snapshot.players.first(where: { $0.id == localParticipantID })?.kind == .human {
            let existing = try context.fetch(
                FetchDescriptor<MedalRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
            )
            var existingByKey = Dictionary(
                existing.map { ($0.logicalKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let issuers = snapshot.players.filter {
                $0.kind == .human && !result.winnerIDs.contains($0.id)
            }
            let winnerPrestige = result.standings.first {
                $0.playerID == localParticipantID
            }?.prestige
            for issuer in issuers {
                let key = MedalRecord.makeLogicalKey(
                    ownerKey: ownerKey,
                    gameID: snapshot.gameID,
                    issuerUUID: issuer.id
                )
                let issuerPrestige = result.standings.first {
                    $0.playerID == issuer.id
                }?.prestige
                let scoreMargin = winnerPrestige.flatMap { winner in
                    issuerPrestige.map { max(0, winner - $0) }
                }

                if let existingMedal = existingByKey[key] {
                    if existingMedal.roomName.isEmpty, !normalizedRoomName.isEmpty {
                        existingMedal.roomName = normalizedRoomName
                        didUpdateMetadata = true
                    }
                    if existingMedal.scoreMargin == nil, let scoreMargin {
                        existingMedal.scoreMargin = scoreMargin
                        didUpdateMetadata = true
                    }
                    continue
                }

                let medal = MedalRecord(
                    ownerKey: ownerKey,
                    issuerUUID: issuer.id,
                    issuerNicknameSnapshot: issuer.nickname,
                    gameID: snapshot.gameID,
                    roomName: normalizedRoomName,
                    scoreMargin: scoreMargin,
                    awardedAt: result.finishedAt
                )
                context.insert(medal)
                existingByKey[key] = medal
                insertedMedals += 1
            }
        }

        if insertedHistory || insertedMedals > 0 || didUpdateMetadata {
            try context.save()
        }
        return MatchOutcomeRecordingResult(
            insertedHistory: insertedHistory,
            insertedMedals: insertedMedals
        )
    }
}

extension Collection where Element == MedalRecord {
    var uniqueScopedMedals: [MedalRecord] {
        var seen: Set<String> = []
        return filter { !$0.ownerKey.isEmpty && seen.insert($0.logicalKey).inserted }
    }
}

extension Collection where Element == CompletedGameRecord {
    var uniqueScopedGames: [CompletedGameRecord] {
        var seen: Set<String> = []
        return filter { !$0.ownerKey.isEmpty && seen.insert($0.logicalKey).inserted }
    }
}
