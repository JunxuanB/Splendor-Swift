import LuminoreCore

@MainActor
extension MatchSessionService {
    func developerSetLocalTokens(_ tokens: [GemColor: Int]) {
        guard DeveloperTools.isEnabledForCurrentBuild,
              isHost,
              phase == .game,
              var state = authoritativeGame,
              state.duel == nil,
              let playerIndex = state.players.firstIndex(where: { $0.id == localID })
        else { return }

        state.players[playerIndex].tokens = normalized(tokens, colors: GemColor.allCases)
        state.revision += 1
        authoritativeGame = state
        broadcastGame()
    }

    func developerSetLocalTokens(_ tokens: [DuelTokenColor: Int]) {
        guard DeveloperTools.isEnabledForCurrentBuild,
              isHost,
              phase == .game,
              var state = authoritativeGame,
              var duel = state.duel,
              let playerIndex = duel.players.firstIndex(where: { $0.id == localID })
        else { return }

        duel.players[playerIndex].tokens = normalized(tokens, colors: DuelTokenColor.allCases)
        state.duel = duel
        state.revision += 1
        authoritativeGame = state
        broadcastGame()
    }

    private func normalized<Color: Hashable>(_ values: [Color: Int], colors: [Color]) -> [Color: Int] {
        Dictionary(uniqueKeysWithValues: colors.compactMap { color in
            let value = max(0, values[color, default: 0])
            return value == 0 ? nil : (color, value)
        })
    }
}
