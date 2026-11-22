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

/// DerindSIP: iOS 26 Phone-style floating bottom bar.
/// A glass pill holding the tabs (Calls · Contacts · Keypad · Messages) and a
/// separate glass circle for search. While searching, both morph into a bottom
/// search field plus a close circle.
struct FloatingTabBar: View {

	@EnvironmentObject var sharedMainViewModel: SharedMainViewModel

	@Binding var searchIsActive: Bool
	@Binding var text: String
	var focusedField: FocusState<Bool>.Binding

	/// Called with the tab index (0 Contacts, 1 Calls, 2 Messages, 4 Keypad).
	let onSelect: (Int) -> Void
	let onOpenSearch: () -> Void
	let onCloseSearch: () -> Void

	@Namespace private var selectionNamespace

	private let barHeight: CGFloat = 62

	private struct TabItem: Identifiable {
		let index: Int
		let icon: String
		let labelKey: String
		let badge: Int
		let accessibilityId: String
		var id: Int { index }
	}

	private var items: [TabItem] {
		var tabs = [
			TabItem(index: 1, icon: "clock.fill", labelKey: "bottom_navigation_calls_label",
					badge: sharedMainViewModel.missedCallsCount, accessibilityId: "bottom_bar_calls_button"),
			TabItem(index: 0, icon: "person.crop.circle.fill", labelKey: "bottom_navigation_contacts_label",
					badge: 0, accessibilityId: "bottom_bar_contacts_button"),
			TabItem(index: 4, icon: "circle.grid.3x3.fill", labelKey: "bottom_navigation_keypad_label",
					badge: 0, accessibilityId: "bottom_bar_keypad_button")
		]
		if !sharedMainViewModel.disableChatFeature {
			tabs.append(TabItem(index: 2, icon: "message.fill", labelKey: "bottom_navigation_conversations_label",
								badge: sharedMainViewModel.unreadMessages, accessibilityId: "bottom_bar_chat_button"))
		}
		return tabs
	}

	var body: some View {
		HStack(spacing: 10) {
			if searchIsActive {
				searchField
				circleButton(systemName: "xmark", accessibilityId: "bottom_bar_close_search_button") {
					onCloseSearch()
				}
			} else {
				pill
				circleButton(systemName: "magnifyingglass", accessibilityId: "bottom_bar_search_button") {
					onOpenSearch()
				}
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 6)
		.padding(.bottom, 4)
		.animation(.spring(response: 0.35, dampingFraction: 0.85), value: searchIsActive)
		.msgDarkScope()
	}

	// MARK: - Tabs pill

	private var pill: some View {
		HStack(spacing: 0) {
			ForEach(items) { item in
				tabButton(item)
			}
		}
		.padding(4)
		.frame(height: barHeight)
		.frame(maxWidth: .infinity)
		.msgGlass(in: Capsule(), interactive: true)
		.transition(.opacity.combined(with: .scale(scale: 0.96)))
	}

	private func tabButton(_ item: TabItem) -> some View {
		let selected = sharedMainViewModel.indexView == item.index
		return Button {
			withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
				onSelect(item.index)
			}
		} label: {
			VStack(spacing: 3) {
				ZStack(alignment: .topTrailing) {
					Image(systemName: item.icon)
						.font(.system(size: 21, weight: .medium))
						.frame(width: 30, height: 26)
					if item.badge > 0 {
						Text(item.badge < 99 ? String(item.badge) : "99+")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.white)
							.lineLimit(1)
							.padding(.horizontal, 5)
							.frame(minWidth: 18, minHeight: 18)
							.background(Capsule().fill(Color.msgMissed))
							.offset(x: 10, y: -6)
					}
				}
				Text(LocalizedStringKey(item.labelKey))
					.font(.system(size: 10, weight: .semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.7)
			}
			.foregroundStyle(selected ? Color.msgAccent : Color.msgTextPrimary)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background {
				if selected {
					Capsule()
						.fill(Color.white.opacity(0.12))
						.matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
				}
			}
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier(item.accessibilityId)
	}

	// MARK: - Search

	private var searchField: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 17, weight: .medium))
				.foregroundStyle(Color.msgTextSecondary)

			TextField(
				"",
				text: $text,
				prompt: Text("bottom_navigation_search_placeholder").foregroundColor(Color.msgTextSecondary)
			)
			.font(.system(size: 17))
			.foregroundStyle(Color.msgTextPrimary)
			.tint(Color.msgAccent)
			.disableAutocorrection(true)
			.autocapitalization(.none)
			.submitLabel(.search)
			.focused(focusedField)
			.accessibilityIdentifier("bottom_bar_search_field")

			if !text.isEmpty {
				Button {
					text = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.font(.system(size: 17))
						.foregroundStyle(Color.msgTextSecondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 18)
		.frame(height: barHeight)
		.frame(maxWidth: .infinity)
		.msgGlass(in: Capsule())
		.transition(.opacity.combined(with: .scale(scale: 0.96)))
		.onAppear {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				focusedField.wrappedValue = true
			}
		}
	}

	private func circleButton(systemName: String, accessibilityId: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemName)
				.font(.system(size: 21, weight: .medium))
				.foregroundStyle(Color.msgTextPrimary)
				.frame(width: barHeight, height: barHeight)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.msgGlass(in: Circle(), interactive: true)
		.accessibilityIdentifier(accessibilityId)
	}
}
