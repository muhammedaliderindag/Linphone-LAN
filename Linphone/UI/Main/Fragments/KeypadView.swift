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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import SwiftUI
import Contacts
import linphonesw

// MARK: - Model

/// Best address-book match for the number typed on the keypad.
struct KeypadMatch: Equatable {
	let name: String
	let label: String
	let address: String
	let friend: Friend?

	static func == (lhs: KeypadMatch, rhs: KeypadMatch) -> Bool {
		lhs.name == rhs.name && lhs.label == rhs.label && lhs.address == rhs.address && lhs.friend === rhs.friend
	}
}

/// DerindSIP: state of the Keypad tab. Kept as a singleton so the typed number
/// survives tab switches, like the iOS Phone app.
final class KeypadViewModel: ObservableObject {

	static let shared = KeypadViewModel()

	@Published var number: String = "" {
		didSet {
			if number != oldValue {
				computeMatch()
			}
		}
	}
	@Published private(set) var match: KeypadMatch?

	private struct Entry {
		let key: String
		let digits: String
		let name: String
		let label: String
		let address: String
		let friend: Friend
	}

	private var entries: [Entry] = []

	private init() {}

	/// Rebuilds the phone number index from every friend list of the core
	/// (native address book, local, CardDAV...). Cheap enough to run on each appear.
	func reloadIndex() {
		CoreContext.shared.doOnCoreQueue { core in
			var tmp: [Entry] = []
			for list in core.friendsLists {
				for friend in list.friends {
					let name = friend.name ?? ""
					guard !name.isEmpty else { continue }
					let address = friend.address?.asStringUriOnly() ?? ""

					for phone in friend.phoneNumbersWithLabel {
						let digits = KeypadViewModel.digits(phone.phoneNumber)
						guard digits.count >= 3 else { continue }
						tmp.append(Entry(
							key: KeypadViewModel.normalize(phone.phoneNumber),
							digits: digits,
							name: name,
							label: KeypadViewModel.displayLabel(phone.label ?? ""),
							address: address,
							friend: friend
						))
					}

					// SIP addresses whose user part is a number (e.g. sip:+905...@host, sip:100@pbx)
					for sipAddress in friend.addresses {
						guard let user = sipAddress.username,
							  !user.isEmpty,
							  user.allSatisfy({ $0.isNumber || $0 == "+" }) else { continue }
						let digits = KeypadViewModel.digits(user)
						guard digits.count >= 3 else { continue }
						tmp.append(Entry(
							key: KeypadViewModel.normalize(user),
							digits: digits,
							name: name,
							label: "SIP",
							address: sipAddress.asStringUriOnly(),
							friend: friend
						))
					}
				}
			}

			tmp.sort {
				$0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
				< $1.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			}

			DispatchQueue.main.async {
				self.entries = tmp
				self.computeMatch()
			}
		}
	}

	private func computeMatch() {
		let typedDigits = KeypadViewModel.digits(number)
		let key = KeypadViewModel.normalize(number)
		guard typedDigits.count >= 3, key.count >= 2 else {
			if match != nil { match = nil }
			return
		}

		let found = entries.first(where: { $0.key == key })
			?? entries.first(where: { $0.digits == typedDigits })
			?? entries.first(where: { $0.key.hasPrefix(key) })
			?? entries.first(where: { $0.digits.hasPrefix(typedDigits) })

		let newMatch = found.map {
			KeypadMatch(name: $0.name, label: $0.label, address: $0.address, friend: $0.friend)
		}
		if newMatch != match {
			match = newMatch
		}
	}

	// MARK: Number helpers

	static func digits(_ raw: String) -> String {
		String(raw.filter { $0.isASCII && $0.isNumber })
	}

	/// Reduces a phone number to a comparable national form so that
	/// "0535 552 66 09", "+90 535 552 66 09", "00905355526609" and
	/// "905355526609" all become "5355526609".
	static func normalize(_ raw: String) -> String {
		var value = KeypadViewModel.digits(raw)
		var international = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
		if value.hasPrefix("00") {
			value.removeFirst(2)
			international = true
		}
		if international || value.count == 12 {
			if value.hasPrefix("90") {
				value.removeFirst(2)
			}
		} else if value.hasPrefix("0") {
			value.removeFirst()
		}
		return value
	}

	/// "Mobile" / "_$!<Mobile>!$_" → localized "cep" / "mobile".
	static func displayLabel(_ raw: String) -> String {
		guard !raw.isEmpty else { return "" }
		let wrapped = raw.hasPrefix("_$!<") ? raw : "_$!<\(raw)>!$_"
		let localized = CNLabeledValue<NSString>.localizedString(forLabel: wrapped)
		if localized.isEmpty || localized.hasPrefix("_$!<") {
			return raw.replacingOccurrences(of: "_$!<", with: "").replacingOccurrences(of: ">!$_", with: "")
		}
		return localized
	}

	// MARK: Actions

	func append(_ character: String) {
		number += character
	}

	func deleteLast() {
		if !number.isEmpty {
			number.removeLast()
		}
	}

	func clear() {
		number = ""
	}

	func playTone(_ character: Character) {
		guard let dtmf = String(character).cString(using: .utf8)?.first else { return }
		CoreContext.shared.doOnCoreQueue { core in
			// Do not play local tones over an ongoing call.
			guard core.callsNb == 0 else { return }
			core.playDtmf(dtmf: dtmf, durationMs: 150)
		}
	}

	/// Green button: empty → recall the last dialed number, otherwise call.
	func callButtonPressed() {
		let action = RedialHelper.onCallButtonPressed(
			currentInput: number.trimmingCharacters(in: .whitespaces),
			lastManuallyDialedNumber: AppServices.corePreferences.lastManuallyDialedNumber
		)
		switch action {
		case .displayLastDialedNumber(let lastNumber):
			number = lastNumber
		case .call(let numberToCall):
			StartCallViewModel.interpretAndStartCall(number: numberToCall)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				self.number = ""
			}
		case .doNothing:
			break
		}
	}
}

// MARK: - View

/// DerindSIP: full screen keypad tab (iOS Phone "Keypad").
struct KeypadView: View {

	@ObservedObject private var viewModel = KeypadViewModel.shared
	@ObservedObject private var contactsManager = ContactsManager.shared

	/// Opens the contact detail for the matched contact.
	let onOpenContact: (ContactAvatarModel) -> Void
	/// Opens the "new contact" editor pre-filled with the typed number.
	let onAddContact: (String) -> Void

	private let keys: [[(digit: String, letters: String)]] = [
		[("1", ""), ("2", "ABC"), ("3", "DEF")],
		[("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
		[("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
		[("*", ""), ("0", "+"), ("#", "")]
	]

	private let feedback = UIImpactFeedbackGenerator(style: .light)

	var body: some View {
		GeometryReader { geometry in
			let layout = metrics(for: geometry.size)

			VStack(spacing: 0) {
				Spacer(minLength: 8)

				numberDisplay
					.frame(height: 56)
					.padding(.horizontal, 24)

				matchRow
					.frame(height: 30)
					.padding(.horizontal, 24)

				Spacer(minLength: 12)

				VStack(spacing: layout.vSpacing) {
					ForEach(0..<keys.count, id: \.self) { row in
						HStack(spacing: layout.hSpacing) {
							ForEach(0..<keys[row].count, id: \.self) { column in
								keyButton(keys[row][column], size: layout.key)
							}
						}
					}

					HStack(spacing: layout.hSpacing) {
						Color.clear
							.frame(width: layout.key, height: layout.key)

						callButton(size: layout.key)

						backspaceButton(size: layout.key)
							.opacity(viewModel.number.isEmpty ? 0 : 1)
							.disabled(viewModel.number.isEmpty)
					}
				}

				Spacer(minLength: 12)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.background(Color.msgBackground.ignoresSafeArea())
		.msgDarkScope()
		.onAppear {
			feedback.prepare()
			viewModel.reloadIndex()
		}
		.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ContactLoaded"))) { _ in
			viewModel.reloadIndex()
		}
	}

	private struct Metrics {
		let key: CGFloat
		let hSpacing: CGFloat
		let vSpacing: CGFloat
	}

	private func metrics(for size: CGSize) -> Metrics {
		// 5 rows of keys (4 digit rows + call row) under ~110pt of number/match display.
		let byHeight = (size.height - 130 - 4 * 16) / 5
		let byWidth = (size.width - 2 * 40 - 2 * 20) / 3
		let key = max(56, min(80, byHeight, byWidth))
		return Metrics(key: key, hSpacing: key * 0.27, vSpacing: key * 0.2)
	}

	// MARK: Display

	private var numberDisplay: some View {
		Text(viewModel.number.isEmpty ? " " : viewModel.number)
			.font(.system(size: 38, weight: .regular))
			.foregroundStyle(Color.msgTextPrimary)
			.lineLimit(1)
			.minimumScaleFactor(0.45)
			.truncationMode(.head)
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
			.contextMenu {
				if !viewModel.number.isEmpty {
					Button {
						UIPasteboard.general.string = viewModel.number
					} label: {
						Label("keypad_copy", systemImage: "doc.on.doc")
					}
				}
				if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
					Button {
						viewModel.number = pasted.filter { $0.isNumber || "+*#".contains($0) }
					} label: {
						Label("keypad_paste", systemImage: "doc.on.clipboard")
					}
				}
			}
			.accessibilityIdentifier("keypad_number")
	}

	@ViewBuilder
	private var matchRow: some View {
		if let match = viewModel.match {
			Button {
				openContact(match)
			} label: {
				HStack(spacing: 6) {
					Text(match.name)
						.font(.system(size: 17, weight: .regular))
						.foregroundStyle(Color.msgAccent)
						.lineLimit(1)
					if !match.label.isEmpty {
						Text(match.label)
							.font(.system(size: 15, weight: .regular))
							.foregroundStyle(Color.msgTextSecondary)
							.lineLimit(1)
					}
				}
			}
			.buttonStyle(.plain)
			.accessibilityIdentifier("keypad_contact_match")
		} else if KeypadViewModel.digits(viewModel.number).count >= 3
					&& !AppServices.corePreferences.disableAddContact
					&& !AppServices.corePreferences.hideContactEdition {
			Button {
				onAddContact(viewModel.number)
			} label: {
				Text("keypad_add_to_contacts")
					.font(.system(size: 17, weight: .regular))
					.foregroundStyle(Color.msgAccent)
			}
			.buttonStyle(.plain)
			.accessibilityIdentifier("keypad_add_contact")
		} else {
			Color.clear
		}
	}

	private func openContact(_ match: KeypadMatch) {
		if let friend = match.friend,
		   let model = contactsManager.avatarListModel.first(where: { $0.friend === friend }) {
			onOpenContact(model)
		} else {
			onOpenContact(ContactAvatarModel(friend: match.friend, name: match.name, address: match.address, withPresence: true))
		}
	}

	// MARK: Keys

	private func keyButton(_ key: (digit: String, letters: String), size: CGFloat) -> some View {
		KeypadKey(
			digit: key.digit,
			letters: key.letters,
			size: size,
			onPress: { press($0) },
			onLongPress: {
				// iOS: holding 0 turns it into "+".
				if viewModel.number.hasSuffix("0") {
					viewModel.deleteLast()
				}
				viewModel.append("+")
				feedback.impactOccurred()
			}
		)
		.accessibilityIdentifier("keypad_key_\(key.digit)")
	}

	private func press(_ digit: String) {
		feedback.impactOccurred()
		viewModel.append(digit)
		if let character = digit.first {
			viewModel.playTone(character)
		}
	}

	private func callButton(size: CGFloat) -> some View {
		Button {
			feedback.impactOccurred()
			viewModel.callButtonPressed()
		} label: {
			Image(systemName: "phone.fill")
				.font(.system(size: size * 0.38, weight: .regular))
				.foregroundStyle(.white)
				.frame(width: size, height: size)
				.background(Circle().fill(Color(red: 0x30/255, green: 0xC7/255, blue: 0x59/255)))
				.contentShape(Circle())
		}
		.buttonStyle(KeypadCallStyle())
		.accessibilityIdentifier("keypad_call_button")
	}

	private func backspaceButton(size: CGFloat) -> some View {
		Button {
			viewModel.deleteLast()
		} label: {
			Image(systemName: "delete.left.fill")
				.font(.system(size: size * 0.3, weight: .regular))
				.foregroundStyle(Color.msgTextSecondary)
				.frame(width: size, height: size)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.simultaneousGesture(
			LongPressGesture(minimumDuration: 0.6).onEnded { _ in
				feedback.impactOccurred()
				viewModel.clear()
			}
		)
		.accessibilityIdentifier("keypad_backspace")
	}
}

/// Dark round key with the iOS "flash" on press. Like the Phone app, the digit
/// registers on touch down; holding the key fires `onLongPress` (used by 0 → +).
private struct KeypadKey: View {
	let digit: String
	let letters: String
	let size: CGFloat
	let onPress: (String) -> Void
	let onLongPress: () -> Void

	@State private var pressed = false
	@State private var longPressWork: DispatchWorkItem?

	var body: some View {
		VStack(spacing: -1) {
			Text(digit)
				.font(.system(size: digit == "*" ? size * 0.5 : size * 0.43,
							  weight: digit == "*" || digit == "#" ? .medium : .regular))
				.padding(.top, digit == "*" ? size * 0.08 : 0)
			if !letters.isEmpty {
				Text(letters)
					.font(.system(size: digit == "0" ? size * 0.2 : size * 0.125, weight: .bold))
					.tracking(digit == "0" ? 0 : 1.5)
					.padding(.top, digit == "0" ? -size * 0.06 : 0)
			}
		}
		.foregroundStyle(Color.msgTextPrimary)
		.frame(width: size, height: size)
		.background(Circle().fill(pressed ? Color(white: 0.45) : Color(white: 0.2)))
		.animation(.easeOut(duration: pressed ? 0.02 : 0.35), value: pressed)
		.contentShape(Circle())
		.gesture(
			DragGesture(minimumDistance: 0)
				.onChanged { _ in
					guard !pressed else { return }
					pressed = true
					onPress(digit)
					if digit == "0" {
						let work = DispatchWorkItem { onLongPress() }
						longPressWork = work
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
					}
				}
				.onEnded { _ in
					pressed = false
					longPressWork?.cancel()
					longPressWork = nil
				}
		)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(digit))
		.accessibilityAddTraits(.isButton)
		.accessibilityAction { onPress(digit) }
	}
}

private struct KeypadCallStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.opacity(configuration.isPressed ? 0.7 : 1)
			.animation(.easeOut(duration: 0.2), value: configuration.isPressed)
	}
}
