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
        context: ModelContext
    ) throws -> MatchOutcomeRecordingResult {
        guard snapshot.status == .finished,
              let result = snapshot.result,
              snapshot.players.contains(where: { $0.id == localParticipantID })
        else {
            return MatchOutcomeRecordingResult(insertedHistory: false, insertedMedals: 0)
        }

        let histories = try context.fetch(
            FetchDescriptor<CompletedGameRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
        )
        let historyKey = CompletedGameRecord.makeLogicalKey(ownerKey: ownerKey, gameID: snapshot.gameID)
        let insertedHistory: Bool
        if histories.contains(where: { $0.logicalKey == historyKey }) {
            insertedHistory = false
        } else {
            context.insert(CompletedGameRecord(
                ownerKey: ownerKey,
                gameID: snapshot.gameID,
                localParticipantID: localParticipantID,
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
            var existingKeys = Set(existing.map(\.logicalKey))
            let issuers = snapshot.players.filter {
                $0.kind == .human && !result.winnerIDs.contains($0.id)
            }
            for issuer in issuers {
                let key = MedalRecord.makeLogicalKey(
                    ownerKey: ownerKey,
                    gameID: snapshot.gameID,
                    issuerUUID: issuer.id
                )
                guard existingKeys.insert(key).inserted else { continue }
                context.insert(MedalRecord(
                    ownerKey: ownerKey,
                    issuerUUID: issuer.id,
                    issuerNicknameSnapshot: issuer.nickname,
                    gameID: snapshot.gameID,
                    awardedAt: result.finishedAt
                ))
                insertedMedals += 1
            }
        }

        if insertedHistory || insertedMedals > 0 {
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
