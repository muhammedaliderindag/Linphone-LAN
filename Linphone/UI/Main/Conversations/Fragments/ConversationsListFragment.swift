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

import SwiftUI
import linphonesw

struct ConversationsListFragment: View {
	
	@Environment(\.scenePhase) var scenePhase
	
	@EnvironmentObject var navigationManager: NavigationManager
	
	@ObservedObject var contactsManager = ContactsManager.shared
	
	@EnvironmentObject var conversationsListViewModel: ConversationsListViewModel
	
	@Binding var text: String
	@Binding var showingSheet: Bool
	
	var body: some View {
		VStack {
			List {
				ForEach(conversationsListViewModel.conversationsList) { conversation in
					ConversationRow(
						navigationManager: _navigationManager,
						conversation: conversation,
						showingSheet: $showingSheet,
						text: $text
					)
				}
				
				if !conversationsListViewModel.currentFilter.isEmpty {
					if !contactsManager.lastSearch.isEmpty {
						HStack(alignment: .center) {
							Text("contacts_list_all_contacts_title")
								.default_text_style_800(styleSize: 16)
							
							Spacer()
						}
					}
					
					ContactsListFragment(showingSheet: .constant(false), startCallFunc: { addr in
						withAnimation {
							conversationsListViewModel.createOneToOneChatRoomWith(remote: addr)
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
					.frame(height: 4)
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
					if conversationsListViewModel.conversationsList.isEmpty &&
						(
							conversationsListViewModel.currentFilter.isEmpty ||
							(!conversationsListViewModel.currentFilter.isEmpty &&
							 contactsManager.lastSearch.isEmpty &&
							 contactsManager.lastSearchSuggestions.isEmpty)
						) {
						Spacer()
						Image(systemName: "message")
							.font(.system(size: 56, weight: .light))
							.foregroundStyle(Color.msgTextTertiary)
							.padding(.all)
						Text(!text.isEmpty ? "list_filter_no_result_found" : "conversations_list_empty")
							.msgText(17, .semibold, color: .msgTextSecondary)
						Spacer()
						Spacer()
					}
				}
					.padding(.all)
			)
			.onDisappear {
				if !conversationsListViewModel.currentFilter.isEmpty {
					conversationsListViewModel.resetFilterConversations()
				}
			}
		}
		.navigationTitle("")
		.navigationBarHidden(true)
		.onChange(of: scenePhase) { newPhase in
			if newPhase == .active {
				if navigationManager.peerAddr != nil {
					conversationsListViewModel.getChatRoomWithStringAddress(stringAddr: navigationManager.peerAddr!)
					navigationManager.peerAddr = nil
				}
			}
		}
	}
	
	var suggestionsList: some View {
		ForEach(0..<contactsManager.lastSearchSuggestions.count, id: \.self) { index in
			Button {
				if let address = contactsManager.lastSearchSuggestions[index].address {
					withAnimation {
						conversationsListViewModel.createOneToOneChatRoomWith(remote: address)
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

struct ConversationRow: View {
	@EnvironmentObject var navigationManager: NavigationManager
	
	@EnvironmentObject var conversationsListViewModel: ConversationsListViewModel
	
	@ObservedObject var conversation: ConversationModel
	
	@Binding var showingSheet: Bool
	@Binding var text: String
	
	var body: some View {
		// DerindSIP: iOS 26 Messages row (unread dot | avatar | name + time > | 2-line preview)
		HStack(alignment: .center, spacing: 8) {
			MsgUnreadDot(visible: conversation.unreadMessagesCount > 0)

			Avatar(contactAvatarModel: conversation.avatarModel, avatarSize: 50)

			VStack(alignment: .leading, spacing: 2) {
				HStack(alignment: .firstTextBaseline, spacing: 6) {
					Text(conversation.subject)
						.msgText(17, .semibold)
						.lineLimit(1)

					Spacer(minLength: 4)

					rowStatusIcons

					Text(conversationsListViewModel.getCallTime(startDate: conversation.lastUpdateTime))
						.msgText(15, color: .msgTextSecondary)
						.lineLimit(1)

					Image(systemName: "chevron.right")
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(Color.msgTextTertiary)
				}

				HStack(alignment: .top, spacing: 0) {
					Text(conversation.lastMessagePrefixText)
						.msgText(15, color: .msgTextSecondary)
						.lineLimit(1)
						.layoutPriority(1)
					
					if !conversation.lastMessageIcon.isEmpty {
						Image(conversation.lastMessageIcon)
							.resizable()
							.frame(width: 16, height: 16)
							.foregroundStyle(Color.msgTextSecondary)
							.layoutPriority(0)
							.padding(.trailing, 2)
					}
					
					if conversation.lastMessageInItalic {
										Text(conversation.lastMessageText)
											.italic()
											.font(.system(size: 15))
											.foregroundStyle(Color.msgTextSecondary)
											.lineLimit(2)
											.layoutPriority(-1)
									} else {
										Text(conversation.lastMessageText)
											.msgText(15, color: .msgTextSecondary)
											.lineLimit(2)
											.multilineTextAlignment(.leading)
											.layoutPriority(-1)
									}
								}
								.frame(maxWidth: .infinity, alignment: .leading)
							}
							.padding(.vertical, 10)
							.overlay(
								Rectangle()
									.fill(Color.msgSeparator)
									.frame(height: 0.5),
								alignment: .bottom
							)
						}
						.frame(minHeight: 76)
						.contentShape(Rectangle())
						.buttonStyle(.borderless)
						.listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 16))
						.listRowSeparator(.hidden)
						.listRowBackground(Color.msgBackground)
						.background(Color.msgBackground)
						.onTapGesture {
							conversationsListViewModel.changeDisplayedChatRoom(conversationModel: conversation)
						}
						.onLongPressGesture(minimumDuration: 0.2) {
							conversationsListViewModel.selectedConversation = conversation
							showingSheet.toggle()
						}
						}

						/// Small state icons next to the time (encryption warning, ephemeral, muted, delivery state).
						@ViewBuilder
						private var rowStatusIcons: some View {
						HStack(spacing: 4) {
						if !conversation.encryptionEnabled && conversation.isEndToEndEncryptionAvailable {
						Image("lock-simple-open")
							.renderingMode(.template)
							.resizable()
							.foregroundStyle(Color.orangeWarning600)
							.frame(width: 14, height: 14)
							}
					
					if conversation.isEphemeral {
						Image("clock-countdown")
							.renderingMode(.template)
							.resizable()
							.foregroundStyle(Color.msgTextSecondary)
							.frame(width: 14, height: 14)
					}
					
					if conversation.isMuted {
						Image("bell-slash")
							.renderingMode(.template)
							.resizable()
							.foregroundStyle(Color.msgTextSecondary)
							.frame(width: 14, height: 14)
					}
					
					if !conversation.lastMessageText.isEmpty
						&& conversation.lastMessageIsOutgoing == true {
						let imageName = LinphoneUtils.getChatIconState(chatState: conversation.lastMessageState)
						Image(imageName)
							.renderingMode(.template)
							.resizable()
								.foregroundStyle(Color.msgTextSecondary)
								.frame(width: 14, height: 14)
							}
							}
							}
}

#Preview {
	ConversationsListFragment(
		text: .constant(""),
		showingSheet: .constant(false)
	)
}
