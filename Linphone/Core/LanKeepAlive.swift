/*
 * Copyright (c) 2010-2023 Belledonne Communications SARL.
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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import AVFoundation
import UIKit

/// LAN-only build helper: keeps the app (and the linphone core) alive in background
/// by looping a silent sound through the `audio` background mode, so a UDP account
/// registered on a local SIP server (no push, no internet) keeps receiving INVITEs.
/// Incoming INVITEs then go through the normal `.IncomingReceived` -> CallKit path.
///
/// All AVAudioSession / player work happens on the main queue; the public methods
/// can be called from any queue.
final class LanKeepAlive {
	static let shared = LanKeepAlive()

	/// Config key `[app] lan_keepalive` (default: on in LAN builds, always off otherwise).
	static var isEnabled: Bool {
#if LAN_BUILD
		return AppServices.configIfAvailable?.getBool(section: "app", key: "lan_keepalive", defaultValue: true) ?? true
#else
		return false
#endif
	}

	private var player: AVAudioPlayer?
	/// True while we want to be kept alive (app in background, no call owning the audio session).
	private var wanted = false
	private var observersInstalled = false

	private init() {}

	/// Start (or keep) looping silence. Idempotent.
	func start() {
		DispatchQueue.main.async {
			self.wanted = true
			self.installObserversIfNeeded()
			self.startPlayer(reason: "start")
		}
	}

	/// Stop looping silence.
	/// - Parameter deactivateSession: true when no call uses the audio session (e.g. returning
	///   to foreground); false when a call (CallKit) now owns the session.
	func stop(deactivateSession: Bool) {
		DispatchQueue.main.async {
			let wasRunning = self.player != nil
			self.wanted = false
			self.player?.stop()
			self.player = nil
			if wasRunning {
				Log.info("[LanKeepAlive] stopped (deactivateSession=\(deactivateSession))")
				if deactivateSession {
					try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
				}
			}
		}
	}

	// MARK: - Private (main queue)

	private func startPlayer(reason: String) {
		guard wanted else { return }
		if let player = player, player.isPlaying {
			return
		}
		let session = AVAudioSession.sharedInstance()
		do {
			try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
			try session.setActive(true)
			if player == nil {
				player = try AVAudioPlayer(data: LanKeepAlive.silentWav())
				player?.numberOfLoops = -1
				player?.volume = 1.0 // samples are all zero anyway
				player?.prepareToPlay()
			}
			if player?.play() == true {
				Log.info("[LanKeepAlive] silent audio running (\(reason)), core stays registered in background")
			} else {
				Log.error("[LanKeepAlive] AVAudioPlayer.play() returned false (\(reason))")
			}
		} catch {
			Log.error("[LanKeepAlive] could not start silent audio (\(reason)): \(error)")
			player = nil
		}
	}

	private func installObserversIfNeeded() {
		guard !observersInstalled else { return }
		observersInstalled = true
		let center = NotificationCenter.default
		center.addObserver(self, selector: #selector(onInterruption(_:)),
						   name: AVAudioSession.interruptionNotification, object: nil)
		center.addObserver(self, selector: #selector(onMediaServicesReset(_:)),
						   name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
	}

	@objc private func onInterruption(_ notification: Notification) {
		guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
			  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
		DispatchQueue.main.async {
			switch type {
			case .began:
				Log.info("[LanKeepAlive] audio interruption began")
			case .ended:
				Log.info("[LanKeepAlive] audio interruption ended, wanted=\(self.wanted)")
				if self.wanted && UIApplication.shared.applicationState == .background
					&& !TelecomManager.shared.callInProgress {
					self.player?.stop()
					self.player = nil
					self.startPlayer(reason: "interruption ended")
				}
			@unknown default:
				break
			}
		}
	}

	@objc private func onMediaServicesReset(_ notification: Notification) {
		DispatchQueue.main.async {
			Log.warn("[LanKeepAlive] media services were reset")
			self.player = nil
			self.startPlayer(reason: "media services reset")
		}
	}

	/// 10 s of 8 kHz mono 16-bit PCM silence, as an in-memory WAV file
	/// (long loop = fewer loop restarts in the player).
	private static func silentWav() -> Data {
		let sampleRate: UInt32 = 8000
		let numSamples: UInt32 = 8000 * 10
		let dataSize = numSamples * 2
		var data = Data()
		func append<T: FixedWidthInteger>(_ value: T) {
			var little = value.littleEndian
			withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
		}
		data.append(contentsOf: Array("RIFF".utf8))
		append(UInt32(36 + dataSize))
		data.append(contentsOf: Array("WAVE".utf8))
		data.append(contentsOf: Array("fmt ".utf8))
		append(UInt32(16))          // fmt chunk size
		append(UInt16(1))           // PCM
		append(UInt16(1))           // mono
		append(sampleRate)
		append(sampleRate * 2)      // byte rate
		append(UInt16(2))           // block align
		append(UInt16(16))          // bits per sample
		data.append(contentsOf: Array("data".utf8))
		append(dataSize)
		data.append(Data(count: Int(dataSize)))
		return data
	}
}
