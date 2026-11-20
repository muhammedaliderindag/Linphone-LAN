/*
 * This file is part of linphone-iphone (DerindSIP fork), licensed under the
 * GNU General Public License v3 or later, like the rest of the project.
 */

// DerindSIP: in-call screen styled after the iOS Phone app.
// Main grid: Speaker / Video / Mute / More / End / Keypad. Every other Linphone in-call
// feature lives in the "More" menu. Actions are the ones of BottomSheetContent.

import SwiftUI
import AVFAudio

enum NativeCallStyle {
	static let backgroundTop = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2D / 255)
	static let backgroundBottom = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
	static let endRed = Color(red: 0xEB / 255, green: 0x4E / 255, blue: 0x3D / 255)
	static let buttonFill = Color.white.opacity(0.18)
	static let secondaryText = Color.white.opacity(0.6)
}

struct NativeCallBackground: View {
	var body: some View {
		LinearGradient(
			colors: [NativeCallStyle.backgroundTop, NativeCallStyle.backgroundBottom],
			startPoint: .top,
			endPoint: .bottom
		)
		.ignoresSafeArea()
	}
}

// MARK: - Header (status line + big name)

struct NativeCallHeader: View {
	@ObservedObject private var telecomManager = TelecomManager.shared
	@EnvironmentObject private var callViewModel: CallViewModel

	/// Digits typed on the in-call keypad; when not empty they replace the name (like iOS).
	var dtmfDigits: String = ""
	var compact: Bool = false
	var onMinimize: () -> Void
	var onEncryptionWarning: () -> Void

	@State private var lastName = ""

	private var shownName: String {
		callViewModel.displayName.isEmpty ? lastName : callViewModel.displayName
	}

	private var showEncryptionWarning: Bool {
		!telecomManager.outgoingCallStarted && telecomManager.callInProgress && !telecomManager.callEnded
		&& ((callViewModel.isMediaEncrypted && callViewModel.isZrtp && !callViewModel.isRemoteDeviceTrusted) || callViewModel.cacheMismatch)
	}

	var body: some View {
		VStack(spacing: compact ? 2 : 6) {
			HStack {
				Button(action: onMinimize) {
					Image(systemName: "chevron.down")
						.font(.system(size: 18, weight: .semibold))
						.foregroundColor(.white.opacity(0.85))
						.frame(width: 44, height: 44)
				}
				Spacer()
				if showEncryptionWarning {
					Button(action: onEncryptionWarning) {
						Image(systemName: "exclamationmark.shield.fill")
							.font(.system(size: 20))
							.foregroundColor(.orange)
							.frame(width: 44, height: 44)
					}
				}
			}
			.padding(.horizontal, 8)

			HStack(spacing: 6) {
				if callViewModel.isRecording && !telecomManager.callEnded {
					Circle()
						.fill(Color.red)
						.frame(width: 8, height: 8)
					Text("REC")
						.font(.system(size: 13, weight: .semibold))
						.foregroundColor(.red)
				}
				Text(callViewModel.callStatusText())
					.font(.system(size: compact ? 15 : 17).monospacedDigit())
					.foregroundColor(NativeCallStyle.secondaryText)
			}

			Text(dtmfDigits.isEmpty ? shownName : dtmfDigits)
				.font(.system(size: compact ? 26 : 34, weight: dtmfDigits.isEmpty ? .semibold : .regular))
				.foregroundColor(.white)
				.lineLimit(dtmfDigits.isEmpty ? 2 : 1)
				.truncationMode(dtmfDigits.isEmpty ? .tail : .head)
				.minimumScaleFactor(0.5)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 24)
		}
		.onAppear {
			if !callViewModel.displayName.isEmpty {
				lastName = callViewModel.displayName
			}
			callViewModel.refreshTimeElapsed()
		}
		.onChange(of: callViewModel.displayName) { newName in
			if !newName.isEmpty {
				lastName = newName
			}
		}
		.onReceive(callViewModel.timer) { _ in
			callViewModel.refreshTimeElapsed()
		}
	}
}

// MARK: - Round button

struct NativeCallButtonLabel: View {
	let systemImage: String
	let title: String
	var isActive: Bool = false
	var fill: Color?
	let size: CGFloat

	var body: some View {
		VStack(spacing: 8) {
			ZStack {
				Circle()
					.fill(fill ?? (isActive ? Color.white : NativeCallStyle.buttonFill))
				Image(systemName: systemImage)
					.font(.system(size: size * 0.36, weight: .medium))
					.foregroundColor(isActive && fill == nil ? .black : .white)
			}
			.frame(width: size, height: size)

			if !title.isEmpty {
				Text(title)
					.font(.system(size: 13))
					.foregroundColor(.white)
					.lineLimit(1)
					.minimumScaleFactor(0.7)
			}
		}
		.frame(width: size + 24)
	}
}

struct NativeCallButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.opacity(configuration.isPressed ? 0.55 : 1)
	}
}

struct NativeCallButton: View {
	let systemImage: String
	let title: String
	var isActive: Bool = false
	var fill: Color?
	let size: CGFloat
	var isEnabled: Bool = true
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			NativeCallButtonLabel(systemImage: systemImage, title: title, isActive: isActive, fill: fill, size: size)
		}
		.buttonStyle(NativeCallButtonStyle())
		.disabled(!isEnabled)
		.opacity(isEnabled ? 1 : 0.35)
	}
}

// MARK: - Controls grid + More menu

struct NativeCallControls: View {
	private enum AudioRoute {
		case earpiece, speaker, bluetooth, headphones
	}

	@ObservedObject private var telecomManager = TelecomManager.shared
	@EnvironmentObject private var callViewModel: CallViewModel

	let isLandscape: Bool
	let buttonSize: CGFloat

	@Binding var optionsAudioRoute: Int
	@Binding var optionsChangeLayout: Int
	@Binding var audioRouteSheet: Bool
	@Binding var changeLayoutSheet: Bool
	@Binding var mediaEncryptedSheet: Bool
	@Binding var callStatisticsSheet: Bool
	@Binding var isShowStartCallFragment: Bool
	@Binding var isShowCallsListFragment: Bool
	@Binding var isShowParticipantsListFragment: Bool
	@Binding var keypadShown: Bool

	@State private var audioRoute: AudioRoute = .earpiece
	@State private var waitingForConversation = false

	private let routeChange = NotificationCenter.default
		.publisher(for: AVAudioSession.routeChangeNotification)
		.receive(on: DispatchQueue.main)

	private var spacing: CGFloat { isLandscape ? 12 : 26 }

	var body: some View {
		Group {
			if isLandscape {
				HStack(spacing: spacing) {
					speakerButton
					videoButton
					muteButton
					moreMenu
					endButton
					keypadButton
				}
			} else {
				VStack(spacing: 22) {
					HStack(spacing: spacing) {
						speakerButton
						videoButton
						muteButton
					}
					HStack(spacing: spacing) {
						moreMenu
						endButton
						keypadButton
					}
				}
			}
		}
		.background(
			// Keeps the audio route icon and the earpiece-only restriction up to date
			// (was in BottomSheetContent).
			Color.clear
				.frame(width: 0, height: 0)
				.onAppear {
					refreshAudioRoute()
					callViewModel.enforceEarpieceIfNeeded()
				}
				.onReceive(routeChange) { _ in
					refreshAudioRoute()
					callViewModel.enforceEarpieceIfNeeded()
				}
		)
		.onChange(of: callViewModel.operationInProgress) { inProgress in
			guard waitingForConversation, !inProgress else { return }
			waitingForConversation = false
			if let conversation = SharedMainViewModel.shared.displayedConversation {
				SharedMainViewModel.shared.changeIndexView(indexViewInt: 2)
				callViewModel.changeDisplayedChatRoom(conversationModel: conversation)
				SharedMainViewModel.shared.displayedConversation = nil
				withAnimation {
					telecomManager.callDisplayed = false
				}
			}
		}
	}

	// MARK: Main buttons

	private var speakerButton: some View {
		let isBluetooth = audioRoute == .bluetooth
		let icon: String = {
			switch audioRoute {
			case .bluetooth: return "airpodspro"
			case .headphones: return "headphones"
			default: return "speaker.wave.2.fill"
			}
		}()
		return NativeCallButton(
			systemImage: icon,
			title: NSLocalizedString(isBluetooth ? "call_native_audio" : "call_native_speaker", comment: ""),
			isActive: audioRoute == .speaker || isBluetooth,
			size: buttonSize,
			isEnabled: !callViewModel.hasAudioRouteRestriction
		) {
			speakerTapped()
		}
	}

	private var videoButton: some View {
		let disabled = SharedMainViewModel.shared.disableVideoCall
			|| callViewModel.isPaused
			|| telecomManager.isPausedByRemote
			|| telecomManager.outgoingCallStarted
			|| telecomManager.callEnded
			|| optionsChangeLayout == 3
		return NativeCallButton(
			systemImage: "video.fill",
			title: NSLocalizedString("call_native_video", comment: ""),
			isActive: callViewModel.videoDisplayed,
			size: buttonSize,
			isEnabled: !disabled
		) {
			if optionsChangeLayout == 3 {
				optionsChangeLayout = 2
				callViewModel.toggleVideoMode(isAudioOnlyMode: false)
			} else {
				callViewModel.displayMyVideo()
			}
		}
	}

	private var muteButton: some View {
		NativeCallButton(
			systemImage: "mic.slash.fill",
			title: NSLocalizedString("call_native_mute", comment: ""),
			isActive: callViewModel.micMutted,
			size: buttonSize,
			isEnabled: !telecomManager.callEnded
		) {
			callViewModel.toggleMuteMicrophone()
		}
	}

	private var endButton: some View {
		NativeCallButton(
			systemImage: "phone.down.fill",
			title: NSLocalizedString("call_native_end", comment: ""),
			fill: NativeCallStyle.endRed,
			size: buttonSize,
			isEnabled: !telecomManager.callEnded
		) {
			callViewModel.terminateCall()
		}
	}

	private var keypadButton: some View {
		NativeCallButton(
			systemImage: "circle.grid.3x3.fill",
			title: NSLocalizedString("call_native_keypad", comment: ""),
			size: buttonSize,
			isEnabled: callViewModel.isOneOneCall && !telecomManager.callEnded
		) {
			withAnimation(.easeInOut(duration: 0.2)) {
				keypadShown = true
			}
		}
	}

	// MARK: More menu

	private var moreMenu: some View {
		Menu {
			if callViewModel.isOneOneCall {
				Button {
					callViewModel.toggleRecording()
				} label: {
					Label(
						NSLocalizedString(callViewModel.isRecording ? "call_native_stop_recording" : "call_native_record", comment: ""),
						systemImage: callViewModel.isRecording ? "stop.circle" : "record.circle"
					)
				}
				.disabled(AppServices.corePreferences.disableCallRecordings || callViewModel.isPaused || telecomManager.isPausedByRemote)
			}

			Button {
				callViewModel.togglePause()
			} label: {
				Label(
					NSLocalizedString(callViewModel.isPaused ? "call_native_resume" : "call_native_hold", comment: ""),
					systemImage: callViewModel.isPaused ? "play.fill" : "pause.fill"
				)
			}
			.disabled(telecomManager.isPausedByRemote)

			Divider()

			Button {
				withAnimation {
					isShowStartCallFragment.toggle()
				}
				refreshCallLayout()
			} label: {
				Label(NSLocalizedString("call_native_add_call", comment: ""), systemImage: "plus")
			}

			if callViewModel.isOneOneCall {
				Button {
					withAnimation {
						callViewModel.isTransferInsteadCall = true
						isShowStartCallFragment.toggle()
					}
					refreshCallLayout()
				} label: {
					Label(NSLocalizedString("call_native_transfer", comment: ""), systemImage: "phone.arrow.right")
				}
			}

			Button {
				callViewModel.getCallsList()
				withAnimation {
					isShowCallsListFragment.toggle()
				}
				refreshCallLayout()
			} label: {
				let title = NSLocalizedString("call_native_calls", comment: "")
				Label(callViewModel.callsCounter > 1 ? "\(title) (\(callViewModel.callsCounter))" : title, systemImage: "list.bullet")
			}

			if !callViewModel.isOneOneCall {
				Button {
					withAnimation {
						isShowParticipantsListFragment.toggle()
					}
				} label: {
					Label(NSLocalizedString("call_native_participants", comment: ""), systemImage: "person.2.fill")
				}

				Button {
					changeLayoutSheet = true
				} label: {
					Label(NSLocalizedString("call_native_layout", comment: ""), systemImage: "square.grid.2x2")
				}
				.disabled(callViewModel.activeSpeakerParticipant?.isScreenSharing == true)
			}

			if !AppServices.corePreferences.disableChatFeature && callViewModel.chatEnabled {
				Button {
					waitingForConversation = true
					callViewModel.createConversation()
				} label: {
					Label(NSLocalizedString("call_native_messages", comment: ""), systemImage: "message.fill")
				}
				.disabled(callViewModel.operationInProgress)
			}

			Divider()

			if callViewModel.videoDisplayed && !callViewModel.isPaused && !telecomManager.isPausedByRemote {
				Button {
					callViewModel.switchCamera()
				} label: {
					Label(NSLocalizedString("call_native_switch_camera", comment: ""), systemImage: "arrow.triangle.2.circlepath.camera")
				}
			}

			if !callViewModel.hasAudioRouteRestriction {
				Button {
					audioRouteSheet = true
				} label: {
					Label(NSLocalizedString("call_native_audio_output", comment: ""), systemImage: "speaker.wave.2")
				}
			}

			Button {
				callStatisticsSheet = true
			} label: {
				Label(NSLocalizedString("call_native_call_quality", comment: ""), systemImage: "chart.bar.fill")
			}

			Button {
				mediaEncryptedSheet = true
			} label: {
				Label(NSLocalizedString("call_native_encryption", comment: ""), systemImage: "lock.fill")
			}

			Divider()

			Button {
				withAnimation {
					telecomManager.callDisplayed = false
				}
			} label: {
				Label(NSLocalizedString("call_native_back_to_app", comment: ""), systemImage: "chevron.down.circle")
			}
		} label: {
			NativeCallButtonLabel(
				systemImage: "ellipsis",
				title: NSLocalizedString("call_native_more", comment: ""),
				size: buttonSize
			)
		}
		.disabled(telecomManager.callEnded)
		.opacity(telecomManager.callEnded ? 0.35 : 1)
	}

	// MARK: Helpers

	private func speakerTapped() {
		let session = AVAudioSession.sharedInstance()
		let hasBluetooth = session.availableInputs?.contains(where: { $0.portType.rawValue.contains("Bluetooth") }) ?? false
		if hasBluetooth {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
				audioRouteSheet = true
			}
		} else {
			let onSpeaker = session.currentRoute.outputs.contains(where: { $0.portType.rawValue == "Speaker" })
			do {
				try session.overrideOutputAudioPort(onSpeaker ? .none : .speaker)
			} catch {
				Log.error("[NativeCallControls] overrideOutputAudioPort failed: \(error)")
			}
		}
	}

	/// Same mapping as BottomSheetContent.getAudioRouteImage() (optionsAudioRoute drives AudioRouteBottomSheet).
	private func refreshAudioRoute() {
		let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
		if outputs.contains(where: { $0.portType.rawValue == "Speaker" }) {
			audioRoute = .speaker
			optionsAudioRoute = 2
		} else if outputs.contains(where: { $0.portType.rawValue.contains("Bluetooth") }) {
			audioRoute = .bluetooth
			optionsAudioRoute = 3
		} else {
			audioRoute = callViewModel.isHeadPhoneAvailable() ? .headphones : .earpiece
			optionsAudioRoute = 1
		}
	}

	/// Same re-layout workaround the old bottom sheet used after opening a call fragment.
	private func refreshCallLayout() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
			telecomManager.callStarted = false
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				telecomManager.callStarted = true
			}
		}
	}
}

// MARK: - In-call keypad (DTMF)

struct NativeKeypad: View {
	@ObservedObject private var telecomManager = TelecomManager.shared
	@EnvironmentObject private var callViewModel: CallViewModel

	@Binding var digits: String
	@Binding var keypadShown: Bool
	let buttonSize: CGFloat

	private let keys: [(digit: String, letters: String)] = [
		("1", ""), ("2", "ABC"), ("3", "DEF"),
		("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
		("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
		("*", ""), ("0", "+"), ("#", "")
	]

	private var rowSpacing: CGFloat { buttonSize * 0.2 }
	private var columnSpacing: CGFloat { buttonSize * 0.36 }

	var body: some View {
		VStack(spacing: rowSpacing) {
			ForEach(0..<4, id: \.self) { row in
				HStack(spacing: columnSpacing) {
					ForEach(0..<3, id: \.self) { col in
						keyButton(keys[row * 3 + col])
					}
				}
			}

			HStack(spacing: columnSpacing) {
				Color.clear
					.frame(width: buttonSize, height: buttonSize)

				NativeCallButton(
					systemImage: "phone.down.fill",
					title: "",
					fill: NativeCallStyle.endRed,
					size: buttonSize,
					isEnabled: !telecomManager.callEnded
				) {
					callViewModel.terminateCall()
				}
				.frame(width: buttonSize, height: buttonSize)

				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						keypadShown = false
						digits = ""
					}
				} label: {
					Text(NSLocalizedString("call_native_hide", comment: ""))
						.font(.system(size: 17))
						.foregroundColor(.white)
						.frame(width: buttonSize, height: buttonSize)
				}
			}
		}
	}

	private func keyButton(_ key: (digit: String, letters: String)) -> some View {
		Button {
			digits.append(key.digit)
			if let ascii = Character(key.digit).asciiValue {
				callViewModel.sendDtmf(dtmf: CChar(ascii))
			}
		} label: {
			ZStack {
				Circle()
					.fill(NativeCallStyle.buttonFill)
				VStack(spacing: -2) {
					Text(key.digit)
						.font(.system(size: buttonSize * (key.digit == "*" ? 0.55 : 0.44), weight: .regular))
						.foregroundColor(.white)
					if !key.letters.isEmpty {
						Text(key.letters)
							.font(.system(size: buttonSize * 0.13, weight: .semibold))
							.kerning(1.5)
							.foregroundColor(.white)
					}
				}
			}
			.frame(width: buttonSize, height: buttonSize)
		}
		.buttonStyle(NativeCallButtonStyle())
	}
}
