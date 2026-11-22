/*
 * Copyright (c) 2010-2026 Belledonne Communications SARL.
 *
 * This file is part of linphone-iphone
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import AVFoundation

/// Plays the busy tone used in Turkey/Europe (425 Hz, 0.5 s on / 0.5 s off) when an
/// outgoing call is refused busy, like the native Phone app.
///
/// It plays on whatever audio session is active. TelecomManager defers the CallKit end
/// while the tone plays, so CallKit keeps the call's playAndRecord session active and the
/// tone goes to the call's current route (receiver, speaker or Bluetooth).
final class BusyTonePlayer {
	static let shared = BusyTonePlayer()

	static let frequency = 425.0
	static let onSeconds = 0.5
	static let offSeconds = 0.5
	static let defaultCycles = 3

	private let queue = DispatchQueue(label: "org.linphone.busytone")
	private var engine: AVAudioEngine?
	private var player: AVAudioPlayerNode?
	private var generation = 0

	private init() {}

	/// Total length of `cycles` on/off periods, in seconds.
	static func duration(cycles: Int = defaultCycles) -> Double {
		return Double(cycles) * (onSeconds + offSeconds)
	}

	func play(cycles: Int = BusyTonePlayer.defaultCycles) {
		queue.async { self.start(cycles: cycles) }
	}

	func stop() {
		queue.async { self.teardown() }
	}

	private func start(cycles: Int) {
		if engine != nil { return }   // already playing

		let engine = AVAudioEngine()
		let player = AVAudioPlayerNode()
		let sampleRate = 44100.0
		guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
			  let buffer = BusyTonePlayer.makeBuffer(format: format, cycles: cycles) else {
			Log.error("[BusyTone] cannot build the tone buffer")
			return
		}

		engine.attach(player)
		engine.connect(player, to: engine.mainMixerNode, format: format)
		do {
			try engine.start()
		} catch {
			Log.error("[BusyTone] engine start failed: \(error.localizedDescription)")
			return
		}

		generation += 1
		let myGeneration = generation
		self.engine = engine
		self.player = player
		player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
			guard let self = self else { return }
			// Let the last samples reach the output before tearing the engine down.
			self.queue.asyncAfter(deadline: .now() + 0.15) {
				if self.generation == myGeneration { self.teardown() }
			}
		}
		player.play()
		Log.info("[BusyTone] playing \(cycles) cycles of \(BusyTonePlayer.frequency) Hz")
	}

	private func teardown() {
		guard let engine = engine else { return }
		player?.stop()
		engine.stop()
		if let player = player { engine.detach(player) }
		self.player = nil
		self.engine = nil
		Log.info("[BusyTone] stopped")
	}

	/// `cycles` x (tone, silence), with short fades so the tone does not click.
	private static func makeBuffer(format: AVAudioFormat, cycles: Int) -> AVAudioPCMBuffer? {
		let sampleRate = format.sampleRate
		let onFrames = Int(sampleRate * onSeconds)
		let periodFrames = Int(sampleRate * (onSeconds + offSeconds))
		let totalFrames = periodFrames * max(cycles, 1)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
			  let samples = buffer.floatChannelData?[0] else {
			return nil
		}
		buffer.frameLength = AVAudioFrameCount(totalFrames)

		let amplitude: Float = 0.3
		let fadeFrames = Int(sampleRate * 0.005)
		let step = 2.0 * Double.pi * frequency / sampleRate
		for i in 0..<totalFrames {
			let pos = i % periodFrames
			if pos >= onFrames {
				samples[i] = 0
				continue
			}
			var gain: Float = 1
			if pos < fadeFrames {
				gain = Float(pos) / Float(fadeFrames)
			} else if pos > onFrames - fadeFrames {
				gain = Float(onFrames - pos) / Float(fadeFrames)
			}
			samples[i] = amplitude * gain * Float(sin(step * Double(pos)))
		}
		return buffer
	}
}
