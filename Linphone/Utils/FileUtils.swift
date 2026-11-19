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

import UIKit
import linphonesw
import UniformTypeIdentifiers

class FileUtil: NSObject {
	
	static let appGroupName: String = resolveAppGroupName()

	/// True when the app group container is accessible. Always true for App Store builds;
	/// false for a LAN build sideloaded with a free Apple ID (e.g. Sideloadly drops app groups).
	static let appGroupAvailable: Bool =
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) != nil

	/// Context for the SDK's Factory.getDataDir/getConfigDir: the app group name, or nil
	/// (= the app's own Library directories) when the group is not accessible.
	/// Passing an inaccessible group crashes the SDK (strlen(NULL) in SysPaths::getDataPath).
	static func sdkPathContext() -> UnsafeMutablePointer<Int8>? {
		guard appGroupAvailable else { return nil }
		return UnsafeMutablePointer<Int8>(mutating: (appGroupName as NSString).utf8String)
	}

	/// Directory containing linphonerc (group container, or the app's own config dir).
	static func linphonercDirectory() -> URL? {
		if appGroupAvailable {
			return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)?
				.appendingPathComponent("Library/Preferences/linphone")
		}
		return URL(fileURLWithPath: Factory.Instance.getConfigDir(context: nil), isDirectory: true)
	}

	/// APP_GROUP_NAME from Info.plist. In LAN builds (sideloaded, re-signed with a free
	/// Apple ID), tools like AltStore/SideStore rename the app group (e.g. append the team id),
	/// so if the declared group is not accessible, use the first accessible group listed in
	/// the app's embedded.mobileprovision instead.
	/// Uses NSLog on purpose: Log itself depends on this value.
	private static func resolveAppGroupName() -> String {
		let declared = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_NAME") as? String
		?? {
			fatalError("APP_GROUP_NAME not defined in Info.plist")
		}()
#if LAN_BUILD
		let fm = FileManager.default
		if fm.containerURL(forSecurityApplicationGroupIdentifier: declared) == nil {
			let provisioned = provisionedAppGroups()
			if let usable = provisioned.first(where: { fm.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }) {
				NSLog("[LAN] app group %@ not accessible, using provisioned group %@", declared, usable)
				return usable
			}
			NSLog("[LAN] app group %@ not accessible and no usable provisioned group (found: %@)", declared, provisioned.joined(separator: ","))
		}
#endif
		return declared
	}

#if LAN_BUILD
	private static func provisionedAppGroups() -> [String] {
		guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
			  let data = try? Data(contentsOf: url),
			  let start = data.range(of: Data("<?xml".utf8)),
			  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
			return []
		}
		let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
		guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
			  let entitlements = plist["Entitlements"] as? [String: Any],
			  let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
			return []
		}
		return groups
	}
#endif
	
	public enum MimeType {
		case plainText
		case pdf
		case image
		case video
		case audio
		case unknown
	}
	
	public class func formUrlEncode(_ inputString: String) -> String {
		// https://www.w3.org/TR/html5/sec-forms.html#application-x-www-form-urlencoded-encoding-algorithm
		// Encode tous les caractères sauf *-._A-Za-z0-9, remplace les espaces par '+'
		
		guard !inputString.isEmpty else {
			return inputString
		}

		// Définir les caractères autorisés (non encodés)
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "*-._")

		// Appliquer l'encodage pour les autres caractères
		var encoded = inputString.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

		// Remplacer les espaces (déjà encodés en %20) par '+'
		encoded = encoded.replacingOccurrences(of: "%20", with: "+")

		return encoded
	}
	
	public class func bundleFilePath(_ file: NSString) -> String? {
		return Bundle.main.path(forResource: file.deletingPathExtension, ofType: file.pathExtension)
	}
	
	public class func bundleFilePathAsUrl(_ file: NSString) -> URL? {
		if let bPath = bundleFilePath(file) {
			return URL.init(fileURLWithPath: bPath)
		}
		return nil
	}
	
	public class func documentsDirectory() -> URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		let documentsDirectory = paths[0]
		return documentsDirectory
	}
	
	public class func libraryDirectory() -> URL {
		let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
		let documentsDirectory = paths[0]
		return documentsDirectory
	}
	
	public class func sharedContainerUrl() -> URL {
		if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) {
			return url
		}
		// Sideloaded builds may be re-signed without the app group: fall back to the
		// app's own Library directory instead of crashing.
		Log.error("App group \(appGroupName) container unavailable, falling back to app Library directory")
		return libraryDirectory()
	}
	
	public class func ensureDirectoryExists(path: String) {
		if !FileManager.default.fileExists(atPath: path) {
			do {
				try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
			} catch {
				print(error)
			}
		}
	}
	
	public class func ensureFileExists(path: String) {
		if !FileManager.default.fileExists(atPath: path) {
			FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
		}
	}
	
	public class func fileExists(path: String) -> Bool {
		return FileManager.default.fileExists(atPath: path)
	}
	
	public class func fileExistsAndIsNotEmpty(path: String) -> Bool {
		guard FileManager.default.fileExists(atPath: path) else {return false}
		do {
			let attribute = try FileManager.default.attributesOfItem(atPath: path)
			if let size = attribute[FileAttributeKey.size] as? NSNumber {
				return size.doubleValue > 0
			} else {
				return false
			}
		} catch {
			print(error)
			return false
		}
	}
	
	public class func write(string: String, toPath: String) {
		do {
			try string.write(to: URL(fileURLWithPath: toPath), atomically: true, encoding: String.Encoding.utf8)
		} catch {
			print(error)
		}
	}
	
	public class func delete(path: String) {
		do {
			try FileManager.default.removeItem(atPath: path)
		} catch {
			print(error)
		}
	}
	
	public class func copy(_ fromPath: String, _ toPath: String, overWrite: Bool) {
		do {
			if overWrite && fileExists(path: toPath) {
				delete(path: toPath)
			}
			try FileManager.default.copyItem(at: URL(fileURLWithPath: fromPath), to: URL(fileURLWithPath: toPath))
		} catch {
			print(error)
		}
	}
	
	// For debugging
	
	public class func showListOfFilesInSharedDir() {
		let fileManager = FileManager.default
		do {
			let fileURLs = try fileManager.contentsOfDirectory(at: FileUtil.sharedContainerUrl(), includingPropertiesForKeys: nil)
			fileURLs.forEach { print($0) }
		} catch {
			print("Error while enumerating files \(error.localizedDescription)")
		}
	}
	
	public class func isExtensionImage(path: String) -> Bool {
		let extensionName = getExtensionFromFileName(fileName: path)
		let typeExtension = getMimeTypeFromExtension(urlString: extensionName)
		return getMimeType(type: typeExtension) == MimeType.image
	}
	
	public class func getExtensionFromFileName(fileName: String) -> String {
		let url: URL? = URL(string: fileName)
		let urlExtension: String? = url?.pathExtension
		
		return urlExtension?.lowercased() ?? ""
	}
	
	public class func getMimeTypeFromExtension(urlString: String?) -> String? {
		if urlString == nil || urlString!.isEmpty {
			return nil
		}
		
		return urlString!.mimeType()
	}
	
	public class func getMimeType(type: String?) -> MimeType {
		if type == nil || type!.isEmpty {
			return MimeType.unknown
		}
		
		switch type {
		case let str where str!.starts(with: "image/"):
			return MimeType.image
		case let str where str!.starts(with: "text/"):
			return MimeType.plainText
		case let str where str!.starts(with: "/log"):
			return MimeType.plainText
		case let str where str!.starts(with: "video/"):
			return MimeType.video
		case let str where str!.starts(with: "audio/"):
			return MimeType.audio
		case let str where str!.starts(with: "application/pdf"):
			return MimeType.pdf
		default:
			return MimeType.unknown
		}
	}
	
	public class func getFileStoragePath(
		fileName: String,
		isImage: Bool = false,
		overrideExisting: Bool = false
	) -> String {
		return getFileStorageDir(fileName: fileName, isPicture: isImage)
	}
	
	public class func getFileStorageDir(fileName: String, isPicture: Bool = false) -> String {
		return Factory.Instance.getDownloadDir(context: nil) + fileName
	}
}

extension NSURL {
	public func mimeType() -> String {
		if let pathExt = self.pathExtension,
			let mimeType = UTType(filenameExtension: pathExt)?.preferredMIMEType {
			return mimeType
		} else {
			return "application/octet-stream"
		}
	}
}

extension URL {
	public func mimeType() -> String {
		if let mimeType = UTType(filenameExtension: self.pathExtension)?.preferredMIMEType {
			return mimeType
		} else {
			return "application/octet-stream"
		}
	}
}

extension NSString {
	public func mimeType() -> String {
		if let mimeType = UTType(filenameExtension: self.pathExtension)?.preferredMIMEType {
			return mimeType
		} else {
			return "application/octet-stream"
		}
	}
}

extension String {
	public func mimeType() -> String {
		return (self as NSString).mimeType()
	}
}
