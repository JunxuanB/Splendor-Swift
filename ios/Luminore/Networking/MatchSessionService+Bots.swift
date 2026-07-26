import Foundation
import LuminoreCore

/// Host-side bot management: adding/removing AI seats in the lobby, and driving
/// their turns during play. Bots live entirely on the authoritative host — the
/// host computes each bot move locally and broadcasts the result like any other
/// action, so all three transports get bots for free with no protocol changes.
extension MatchSessionService {
    /// Seconds a bot "thinks" before playing, so humans can follow its move.
    private var botThinkDelay: TimeInterval { 0.7 }

    // MARK: - Lobby management (host only)

    func addBot(difficulty: BotDifficulty) {
        guard isHost, var room,
              room.descriptor.stage == .lobby || room.descriptor.stage == .configuration
        else { return }
        guard room.participants.count < room.descriptor.maximumPlayers else {
            presentedError = String(localized: "lobby.bot.full")
            return
        }
        let bot = Participant(
            id: UUID(),
            nickname: Self.botNickname(for: difficulty, in: room.participants),
            kind: .bot,
            difficulty: difficulty
        )
        room.participants.append(bot)
        room.descriptor.playerCount = room.participants.count
        room.revision += 1
        self.room = room
        updateAdvertisement()
        broadcastRoom()
    }

    func removeBot(id: UUID) {
        guard isHost, var room,
              let index = room.participants.firstIndex(where: { $0.id == id && $0.kind == .bot })
        else { return }
        room.participants.remove(at: index)
        room.descriptor.playerCount = room.participants.count
        room.revision += 1
        self.room = room
        updateAdvertisement()
        broadcastRoom()
    }

    static func botNickname(for difficulty: BotDifficulty, in participants: [Participant]) -> String {
        let base: String
        switch difficulty {
        case .easy: base = String(localized: "bot.name.easy")
        case .normal: base = String(localized: "bot.name.normal")
        case .hard: base = String(localized: "bot.name.hard")
        }
        let index = participants.count(where: { $0.kind == .bot }) + 1
        return "\(base) \(index)"
    }

    // MARK: - Turn driving (host only)

    /// If the authoritative game's current seat is a bot, schedule it to compute
    /// and apply its move. Re-entrant safe: cancels any pending bot task and only
    /// acts if the game state is unchanged when the computation finishes. Called
    /// after every broadcast (`scheduleGameBroadcast`), after the opening turn, and
    /// on resume — so it also handles Duel optional sub-actions, where the same bot
    /// remains the current player across multiple invocations.
    func scheduleBotTurnIfNeeded() {
        guard isHost, !isPaused, !isOpeningTurnSelection else { return }
        guard let state = authoritativeGame, state.status == .playing else { return }
        let currentID = state.currentPlayer.id
        guard let participant = room?.participants.first(where: { $0.id == currentID }),
              participant.kind == .bot else { return }

        let difficulty = participant.difficulty ?? .normal
        let mode = state.configuration.mode
        let revision = state.revision
        let delay = botThinkDelay

        botTask?.cancel()
        botTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            // GameState is a Sendable value type — computing the move off the main
            // actor keeps the UI responsive on slower host devices.
            let controller = BotFactory.make(for: mode)
            let action = controller.chooseAction(state: state, playerID: currentID, difficulty: difficulty)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                guard self.isHost, !self.isPaused, !self.isOpeningTurnSelection,
                      let live = self.authoritativeGame, live.status == .playing,
                      live.revision == revision, live.currentPlayer.id == currentID
                else { return }
                self.apply(action, from: currentID, allowsPass: true)
            }
        }
    }
}
