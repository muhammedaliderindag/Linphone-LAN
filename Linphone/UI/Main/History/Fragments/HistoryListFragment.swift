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

// swiftlint:disable line_length

import SwiftUI
import linphonesw

struct HistoryListFragment: View {
	
	@ObservedObject var contactsManager = ContactsManager.shared
	@ObservedObject private var telecomManager = TelecomManager.shared
	
	@EnvironmentObject var historyListViewModel: HistoryListViewModel
	
	@Binding var showingSheet: Bool
	@Binding var text: String
	
	var body: some View {
		VStack(spacing: 0) {
			callLogsFilterTabs
			
			List {
				ForEach(historyListViewModel.callLogs) { historyModel in
					HistoryRow(historyModel: historyModel, showingSheet: $showingSheet)
				}
				
				if !historyListViewModel.callLogsFilter.isEmpty && !historyListViewModel.missedCallsOnly {
					if !contactsManager.lastSearch.isEmpty {
						HStack(alignment: .center) {
							Text("contacts_list_all_contacts_title")
								.default_text_style_800(styleSize: 16)
							
							Spacer()
						}
					}
					
					ContactsListFragment(showingSheet: .constant(false), startCallFunc: { addr in
						withAnimation {
							telecomManager.doCallOrJoinConf(address: addr)
						}
					})
					
					if !contactsManager.lastSearchSuggestions.isEmpty {
						HStack(alignment: .center) {
							Text("generic_address_picker_suggestions_list_title")
								.default_text_style_800(styleSize: 16)
							
							Spacer()
						}
						
						suggestionsList
					}
				}
			}
			.safeAreaInset(edge: .top, content: {
				Spacer()
					.frame(height: 6)
			})
			.listStyle(.plain)
			.msgHideScrollBackground()
			.background(Color.msgBackground)
			.onAppear {
				// iOS 15: List has no scrollContentBackground
				UITableView.appearance().backgroundColor = .clear
			}
			.overlay(
				VStack {
					if historyListViewModel.callLogs.isEmpty &&
						(
							historyListViewModel.callLogsFilter.isEmpty ||
							historyListViewModel.missedCallsOnly ||
							(!historyListViewModel.callLogsFilter.isEmpty &&
							 contactsManager.lastSearch.isEmpty &&
							 contactsManager.lastSearchSuggestions.isEmpty)
						) {
						Spacer()
						Image(systemName: "phone")
							.font(.system(size: 56, weight: .light))
							.foregroundStyle(Color.msgTextTertiary)
							.padding(.all)
						Text(!text.isEmpty ? "list_filter_no_result_found" : (historyListViewModel.missedCallsOnly ? "history_list_empty_missed_history" : "history_list_empty_history"))
							.msgText(17, .semibold, color: .msgTextSecondary)
							.multilineTextAlignment(.center)
						Spacer()
						Spacer()
					}
				}
					.padding(.all)
			)
			.onDisappear {
				if !historyListViewModel.callLogsFilter.isEmpty {
					historyListViewModel.resetFilterCallLogs()
				}
				historyListViewModel.setMissedCallsOnly(false)
			}
		}
		.onAppear {
			historyListViewModel.setMissedCallsOnly(false)
		}
		.navigationTitle("")
		.navigationBarHidden(true)
	}
	
	var callLogsFilterTabs: some View {
		HStack(spacing: 0) {
			callLogsFilterTab(title: "history_list_filter_all", isSelected: !historyListViewModel.missedCallsOnly) {
				historyListViewModel.setMissedCallsOnly(false)
			}
			
			callLogsFilterTab(title: "history_list_filter_missed", isSelected: historyListViewModel.missedCallsOnly) {
				historyListViewModel.setMissedCallsOnly(true)
			}
		}
		.padding(2)
		.background(Color.msgFieldBackground)
		.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
		.padding(.horizontal, 16)
		.padding(.top, 8)
		.padding(.bottom, 4)
	}
	
	func callLogsFilterTab(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.system(size: 14, weight: isSelected ? .semibold : .medium))
				.foregroundStyle(Color.msgTextPrimary)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.frame(maxWidth: .infinity)
				.frame(height: 30)
				.background(isSelected ? Color.msgElevated : Color.clear)
				.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}
	
	var suggestionsList: some View {
		ForEach(0..<contactsManager.lastSearchSuggestions.count, id: \.self) { index in
			Button {
				if let address = contactsManager.lastSearchSuggestions[index].address {
					withAnimation {
						telecomManager.doCallOrJoinConf(address: address)
					}
				}
			} label: {
				HStack {
					if index < contactsManager.lastSearchSuggestions.count
						&& contactsManager.lastSearchSuggestions[index].address != nil {
						if contactsManager.lastSearchSuggestions[index].address!.domain != AppServices.corePreferences.defaultDomain {
							Image(uiImage: contactsManager.textToImage(
								firstName: String(contactsManager.lastSearchSuggestions[index].address!.asStringUriOnly().dropFirst(4)),
								lastName: ""))
							.resizable()
							.frame(width: 45, height: 45)
							.clipShape(Circle())
							
							Text(String(contactsManager.lastSearchSuggestions[index].address!.asStringUriOnly().dropFirst(4)))
								.default_text_style(styleSize: 16)
								.lineLimit(1)
								.frame(maxWidth: .infinity, alignment: .leading)
								.foregroundStyle(Color.msgAccent)
						} else {
							if let address = contactsManager.lastSearchSuggestions[index].address {
								let nameTmp = address.displayName
								?? address.username
								?? String(address.asStringUriOnly().dropFirst(4))
								
								Image(uiImage: contactsManager.textToImage(
									firstName: nameTmp,
									lastName: ""))
								.resizable()
								.frame(width: 45, height: 45)
								.clipShape(Circle())
								
								Text(nameTmp)
									.default_text_style(styleSize: 16)
									.lineLimit(1)
									.frame(maxWidth: .infinity, alignment: .leading)
									.foregroundStyle(Color.msgAccent)
							}
						}
					} else {
						Image("profil-picture-default")
							.resizable()
							.frame(width: 45, height: 45)
							.clipShape(Circle())
						
						Text("username_error")
							.default_text_style(styleSize: 16)
							.frame(maxWidth: .infinity, alignment: .leading)
							.foregroundStyle(Color.msgAccent)
					}
				}
			}
			.buttonStyle(.borderless)
			.listRowSeparator(.hidden)
			.listRowBackground(Color.msgBackground)
			}
			}
			}

struct HistoryRow: View {
	@ObservedObject var contactsManager = ContactsManager.shared
	@ObservedObject private var telecomManager = TelecomManager.shared
	
	@EnvironmentObject var historyListViewModel: HistoryListViewModel
	
	@ObservedObject var historyModel: HistoryModel
	
	@Binding var showingSheet: Bool

	// DerindSIP: iOS Recents row — avatar | name (red when missed) + direction | time (i)
	var body: some View {
		HStack(spacing: 10) {
			rowAvatar

			VStack(alignment: .leading, spacing: 1) {
				Text(historyModel.isConf ? historyModel.subject : historyModel.addressName)
					.msgText(17, .semibold, color: historyModel.isMissed ? Color.msgMissed : Color.msgTextPrimary)
					.lineLimit(1)

				HStack(spacing: 5) {
					let iconName = historyListViewModel.getCallIconResId(callStatus: historyModel.status, isOutgoing: historyModel.isOutgoing)
					Image(iconName)
						.resizable()
						.frame(
							width: iconName.contains("rejected") ? 12 : 9,
							height: iconName.contains("rejected") ? 6 : 9
						)

					Text(historyListViewModel.getCallText(callStatus: historyModel.status, isOutgoing: historyModel.isOutgoing))
						.msgText(15, color: .msgTextSecondary)
						.lineLimit(1)
				}
			}

			Spacer(minLength: 4)

			Text(recentTime)
				.msgText(15, color: .msgTextSecondary)
				.lineLimit(1)

			Image(systemName: "info.circle")
				.font(.system(size: 21, weight: .regular))
				.foregroundStyle(Color.msgAccent)
				.frame(width: 32, height: 44)
				.contentShape(Rectangle())
				.highPriorityGesture(
					TapGesture()
						.onEnded { _ in
							withAnimation {
								SharedMainViewModel.shared.displayedCall = historyModel
							}
						}
				)
		}
		.padding(.vertical, 6)
		.overlay(
			Rectangle()
				.fill(Color.msgSeparator)
				.frame(height: 0.5)
				.padding(.leading, 50),
			alignment: .bottom
		)
		.frame(minHeight: 60)
		.contentShape(Rectangle())
		.buttonStyle(.borderless)
		.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.msgBackground)
		.background(Color.msgBackground)
		.onTapGesture {
			withAnimation {
				if historyModel.isConf {
					SharedMainViewModel.shared.displayedCall = historyModel
				} else {
					// iOS Recents: tapping a row calls back
					doCall(historyModel: historyModel)
					SharedMainViewModel.shared.displayedCall = nil
				}
			}
		}
		.onLongPressGesture(minimumDuration: 0.2) {
			historyListViewModel.selectedCall = historyModel
			showingSheet.toggle()
		}
	}

	@ViewBuilder
	private var rowAvatar: some View {
		if !historyModel.isConf {
			if historyModel.avatarModel != nil {
				Avatar(contactAvatarModel: historyModel.avatarModel!, avatarSize: 40)
			} else if !historyModel.addressName.isEmpty {
				Image(uiImage: contactsManager.textToImage(
					firstName: historyModel.addressName,
					lastName: historyModel.addressName.components(separatedBy: " ").count > 1
					? historyModel.addressName.components(separatedBy: " ")[1]
					: ""))
				.resizable()
				.frame(width: 40, height: 40)
				.clipShape(Circle())
			} else {
				Image(systemName: "person.fill")
					.font(.system(size: 20))
					.foregroundStyle(Color.msgTextBody)
					.frame(width: 40, height: 40)
					.background(Circle().fill(Color.msgElevated))
			}
		} else {
			Image("video-conference")
				.renderingMode(.template)
				.resizable()
				.frame(width: 22, height: 22)
				.foregroundStyle(Color.msgTextBody)
				.frame(width: 40, height: 40)
				.background(Circle().fill(Color.msgElevated))
		}
	}

	/// iOS-like relative time: today -> time, yesterday -> "Yesterday", this week -> weekday, else short date.
	private var recentTime: String {
		let date = Date(timeIntervalSince1970: TimeInterval(historyModel.startDate))
		let calendar = Calendar.current
		let formatter = DateFormatter()
		if calendar.isDateInToday(date) {
			formatter.dateStyle = .none
			formatter.timeStyle = .short
		} else if calendar.isDateInYesterday(date) {
			formatter.doesRelativeDateFormatting = true
			formatter.dateStyle = .short
			formatter.timeStyle = .none
		} else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
			formatter.setLocalizedDateFormatFromTemplate("EEEE")
		} else {
			formatter.dateStyle = .short
			formatter.timeStyle = .none
		}
		return formatter.string(from: date)
	}

	func doCall(historyModel: HistoryModel) {
		telecomManager.doCallOrJoinConf(address: historyModel.addressLinphone)
	}
}

#Preview {
	HistoryListFragment(showingSheet: .constant(false), text: .constant(""))
}

// swiftlint:enable line_length
