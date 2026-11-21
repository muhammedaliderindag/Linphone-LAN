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

#if LAN_BUILD

import CoreLocation
import UIKit

/// LAN-only build: wakes the app through iBeacon region monitoring.
/// An Android phone advertises an iBeacon (UUID below, major 1..4 chosen by the bridge (least recently used) per event,
/// minor 1) when a call/SMS arrives; CoreLocation relaunches/wakes the app in background
/// (~10 s), we re-REGISTER immediately and the SIP bridge then sends the INVITE, which goes
/// through the normal `.IncomingReceived` -> CallKit path.
///
/// Needs Location = Always + Precise. No `location` UIBackgroundMode is required for region monitoring.
final class LanBeaconWake: NSObject, CLLocationManagerDelegate {
	static let shared = LanBeaconWake()

	static let uuid = UUID(uuidString: "85AF35C8-7589-487B-8CF0-05C61AD6441C")!
	static let majors: [CLBeaconMajorValue] = [1, 2, 3, 4]
	static let identifierPrefix = "derind.beacon."

	private var manager: CLLocationManager?
	private var lastWake: Date?

	private override init() {
		super.init()
	}

	private static func identifier(for major: CLBeaconMajorValue) -> String {
		return "\(identifierPrefix)\(major)"
	}

	/// Start monitoring the beacon regions. Idempotent, main thread.
	func start() {
		if !Thread.isMainThread {
			DispatchQueue.main.async { self.start() }
			return
		}
		if manager == nil {
			let m = CLLocationManager()
			m.delegate = self
			manager = m
			Log.info("[LanBeacon] location manager created")
		}
		guard let manager = manager else { return }

		logAuthorization(prefix: "start")
		switch manager.authorizationStatus {
		case .notDetermined, .authorizedWhenInUse:
			manager.requestAlwaysAuthorization()
		default:
			break
		}
		setupMonitoring()
	}

	/// Stop monitoring our beacon regions (silent-audio keep-alive selected in Settings). Main thread.
	func stop() {
		if !Thread.isMainThread {
			DispatchQueue.main.async { self.stop() }
			return
		}
		let m = manager ?? CLLocationManager()
		for region in m.monitoredRegions where region.identifier.hasPrefix(LanBeaconWake.identifierPrefix) {
			m.stopMonitoring(for: region)
		}
		Log.info("[LanBeacon] stopped monitoring beacon regions")
	}

	/// Settings toggle: switch between iBeacon wake (default) and the silent-audio keep-alive.
	/// Called after `[app] lan_keepalive` was written. Takes effect immediately (keep-alive starts
	/// at the next background transition).
	static func applyWakeMode(keepAlive: Bool) {
		Log.info("[LanBeacon] wake mode changed: \(keepAlive ? "silent-audio keep-alive" : "iBeacon")")
		if keepAlive {
			shared.stop()
		} else {
			LanKeepAlive.shared.stop(deactivateSession: true)
			shared.start()
		}
	}

	private func logAuthorization(prefix: String) {
		guard let manager = manager else { return }
		let status = manager.authorizationStatus
		let accuracy = manager.accuracyAuthorization
		Log.info("[LanBeacon] \(prefix): authorizationStatus=\(status.rawValue) accuracyAuthorization=\(accuracy.rawValue)")
		if status != .authorizedAlways || accuracy == .reducedAccuracy {
			Log.warn("[LanBeacon] beacon wake needs Location=Always + Precise (status=\(status.rawValue) accuracy=\(accuracy.rawValue))")
		}
	}

	private func setupMonitoring() {
		guard let manager = manager else { return }
		guard CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) else {
			Log.error("[LanBeacon] region monitoring for beacons is not available on this device")
			return
		}

		let ourIdentifiers = Set(LanBeaconWake.majors.map { LanBeaconWake.identifier(for: $0) })
		for region in manager.monitoredRegions where region.identifier.hasPrefix(LanBeaconWake.identifierPrefix)
			&& !ourIdentifiers.contains(region.identifier) {
			Log.info("[LanBeacon] stop monitoring stale region \(region.identifier)")
			manager.stopMonitoring(for: region)
		}

		for major in LanBeaconWake.majors {
			let id = LanBeaconWake.identifier(for: major)
			let region = CLBeaconRegion(uuid: LanBeaconWake.uuid, major: major, identifier: id)
			region.notifyOnEntry = true
			region.notifyOnExit = true
			region.notifyEntryStateOnDisplay = true
			manager.startMonitoring(for: region)
			manager.requestState(for: region)
			Log.info("[LanBeacon] monitoring \(id) (uuid=\(LanBeaconWake.uuid.uuidString) major=\(major))")
		}
	}

	private func wake(reason: String) {
		let now = Date()
		if let last = lastWake, now.timeIntervalSince(last) < 3 {
			Log.info("[LanBeacon] wake ignored (debounce): \(reason)")
			return
		}
		lastWake = now
		Log.info("[LanBeacon] wake: \(reason)")
		CoreContext.shared.onBeaconWake(reason: reason)
	}

	// MARK: - CLLocationManagerDelegate

	func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
		wake(reason: "didEnterRegion \(region.identifier)")
	}

	func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
		Log.info("[LanBeacon] didExitRegion \(region.identifier)")
	}

	func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
		Log.info("[LanBeacon] didDetermineState \(state.rawValue) for \(region.identifier)")
		if state == .inside {
			wake(reason: "didDetermineState inside \(region.identifier)")
		}
	}

	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		logAuthorization(prefix: "authorization changed")
		switch manager.authorizationStatus {
		case .authorizedAlways, .authorizedWhenInUse:
			setupMonitoring()
		default:
			break
		}
	}

	func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
		Log.error("[LanBeacon] monitoringDidFailFor \(region?.identifier ?? "nil"): \(error)")
	}

	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		Log.error("[LanBeacon] didFailWithError: \(error)")
	}
}

#endif
