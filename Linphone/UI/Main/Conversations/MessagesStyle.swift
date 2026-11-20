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

// DerindSIP iOS 26 Messages-style dark look for the conversations screens
// and the app shell (header, tab bar, landscape rail). Always dark,
// independent of the system appearance.

import SwiftUI

extension Color {
	static let msgBackground = Color(red: 0, green: 0, blue: 0)
	static let msgBubbleOut = Color(red: 0x30/255, green: 0xD1/255, blue: 0x58/255)
	static let msgBubbleIn = Color(red: 0x26/255, green: 0x26/255, blue: 0x28/255)
	static let msgTextPrimary = Color(red: 1, green: 1, blue: 1)
	static let msgTextBody = Color(red: 0xEB/255, green: 0xEB/255, blue: 0xF0/255)
	static let msgTextSecondary = Color(red: 0x8E/255, green: 0x8E/255, blue: 0x93/255)
	static let msgTextTertiary = Color(red: 0x63/255, green: 0x63/255, blue: 0x66/255)
	static let msgSeparator = Color(red: 0x38/255, green: 0x38/255, blue: 0x3A/255)
	static let msgAccent = Color(red: 0x0A/255, green: 0x84/255, blue: 0xFF/255)
	static let msgGreen = Color(red: 0x30/255, green: 0xD1/255, blue: 0x58/255)
	static let msgFieldBackground = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
	static let msgFieldStroke = Color(red: 0x3A/255, green: 0x3A/255, blue: 0x3C/255)
	static let msgBar = Color(red: 0x12/255, green: 0x12/255, blue: 0x13/255)
	static let msgElevated = Color(red: 0x2C/255, green: 0x2C/255, blue: 0x2E/255)
	static let msgMissed = Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255)
	static let msgOutgoingMeta = Color(red: 1, green: 1, blue: 1).opacity(0.75)
}

enum MessagesStyle {
	static let bubbleRadius: CGFloat = 18
	static let uiBackground = UIColor.black
}

// MARK: - Dark scope

private struct MsgDarkKey: EnvironmentKey {
	static let defaultValue: Bool = false
}

extension EnvironmentValues {
	/// True inside the DerindSIP dark Messages screens. Deliberately separate from
	/// `colorScheme` so that a phone in system dark mode does not recolor the
	/// light-only Contacts/Calls/Meetings screens.
	var msgDark: Bool {
		get { self[MsgDarkKey.self] }
		set { self[MsgDarkKey.self] = newValue }
	}
}

/// Foreground used by the shared `default_text_style*` helpers: the original
/// Linphone color normally, a light equivalent inside a Messages dark scope.
struct MsgAdaptiveForeground: ViewModifier {
	@Environment(\.msgDark) private var msgDark
	let light: Color
	let dark: Color

	func body(content: Content) -> some View {
		content.foregroundStyle(msgDark ? dark : light)
	}
}

/// Background that follows the Messages dark scope (for components shared with
/// the light Contacts/Meetings screens).
struct MsgAdaptiveBackground: ViewModifier {
	@Environment(\.msgDark) private var msgDark
	let light: Color
	let dark: Color

	func body(content: Content) -> some View {
		content.background(msgDark ? dark : light)
	}
}

extension View {
	func msgAdaptiveForeground(_ light: Color, _ dark: Color) -> some View {
		self.modifier(MsgAdaptiveForeground(light: light, dark: dark))
	}

	func msgAdaptiveBackground(_ light: Color, _ dark: Color) -> some View {
		self.modifier(MsgAdaptiveBackground(light: light, dark: dark))
	}

	/// Marks a subtree as DerindSIP dark Messages UI.
	func msgDarkScope() -> some View {
		self
			.environment(\.msgDark, true)
			.environment(\.colorScheme, .dark)
	}

	/// Same as `msgDarkScope` for content presented in its own UIKit container
	/// (sheets, full screen covers): also sets the presentation's appearance.
	func msgDarkPresentation() -> some View {
		self
			.msgDarkScope()
			.preferredColorScheme(.dark)
	}

	func msgText(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color = .msgTextPrimary) -> some View {
		self
			.font(.system(size: size, weight: weight))
			.foregroundStyle(color)
	}

	@ViewBuilder
	func msgHideScrollBackground() -> some View {
		if #available(iOS 16.0, *) {
			self.scrollContentBackground(.hidden)
		} else {
			self
		}
	}

	/// Hairline separator along the top or bottom edge of a bar.
	func msgHairline(_ edge: VerticalEdge) -> some View {
		self.overlay(
			Rectangle()
				.fill(Color.msgSeparator)
				.frame(height: 0.5),
			alignment: edge == .top ? .top : .bottom
		)
	}
}

// MARK: - Small reusable pieces

/// iOS-style round icon button (gray circle, white glyph).
struct MsgCircleButton: View {
	let systemName: String
	var size: CGFloat = 34
	var glyphSize: CGFloat = 16
	var fill: Color = .msgElevated
	var tint: Color = .msgTextPrimary
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: systemName)
				.font(.system(size: glyphSize, weight: .semibold))
				.foregroundStyle(tint)
				.frame(width: size, height: size)
				.background(Circle().fill(fill))
		}
		.buttonStyle(.plain)
	}
}

/// Unread indicator dot shown at the leading edge of a conversation row.
struct MsgUnreadDot: View {
	let visible: Bool

	var body: some View {
		Circle()
			.fill(visible ? Color.msgAccent : Color.clear)
			.frame(width: 10, height: 10)
	}
}
