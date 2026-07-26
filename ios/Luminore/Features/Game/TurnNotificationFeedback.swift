import AVFAudio
import SwiftUI
import UIKit

/// A single local-only notification for every game variant and transport.
/// The ambient audio category follows the device's Silent Mode setting.
@MainActor
private final class TurnNotificationFeedback {
    static let shared = TurnNotificationFeedback()

    private var audioPlayer: AVAudioPlayer?
    private lazy var chimeData = Self.makeChimeData()

    func play() {
        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.prepare()
        haptic.impactOccurred(intensity: 1)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(data: chimeData)
            player.volume = 0.75
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            // Audio must never interrupt the game or suppress the haptic reminder.
        }
    }

    /// Builds a short two-note PCM chime in memory so the reminder has no asset or
    /// file-loading dependency. This also keeps it identical in every game mode.
    private static func makeChimeData() -> Data {
        let sampleRate = 44_100
        let duration = 0.32
        let sampleCount = Int(Double(sampleRate) * duration)
        let dataByteCount = sampleCount * MemoryLayout<Int16>.size
        var data = Data()

        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + dataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * MemoryLayout<Int16>.size))
        data.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(dataByteCount))

        for sampleIndex in 0 ..< sampleCount {
            let time = Double(sampleIndex) / Double(sampleRate)
            let attack = min(time / 0.012, 1)
            let decay = exp(-5.2 * time / duration)
            let lowerNote = sin(2 * Double.pi * 1_046.50 * time)
            let upperNote = sin(2 * Double.pi * 1_318.51 * time)
            let sample = attack * decay * (0.62 * lowerNote + 0.38 * upperNote)
            data.appendLittleEndian(Int16(sample * Double(Int16.max) * 0.68))
        }

        return data
    }
}

private struct LocalTurnNotificationModifier: ViewModifier {
    let isLocalTurn: Bool
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                if isLocalTurn { TurnNotificationFeedback.shared.play() }
            }
            .onChange(of: isLocalTurn) { wasLocalTurn, isLocalTurn in
                guard hasAppeared, !wasLocalTurn, isLocalTurn else { return }
                TurnNotificationFeedback.shared.play()
            }
    }
}

extension View {
    func localTurnNotification(isLocalTurn: Bool) -> some View {
        modifier(LocalTurnNotificationModifier(isLocalTurn: isLocalTurn))
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
