//
//  EuropeCCIFingerprint.swift
//  BetterBlueKit
//
//  X-Fingerprint signing for the EU OneApp/CCI auth endpoints.
//
//  Since 2026-10-13/14 cci-api-eu.{brand}.com rejects unsigned POSTs to its
//  /auth endpoints: 9035 when X-Fingerprint is missing (served to users as
//  "Unusual activity has been detected so you've been logged out"), 9036 for
//  a wrong signature, 9037 for an X-Timestamp more than ~120 s out. Ported
//  from hyundai_kia_connect_api 97668164 (cci_fingerprint.py), which
//  recovered the scheme and the per-brand constants from the Android
//  OneApp 1.4.0 build and verified them live for Hyundai and Kia.
//
//  The constants rotate with OneApp releases. When sign-in starts failing
//  with 9036, check upstream for new ones before anything else.
//

import CryptoKit
import Foundation

enum EuropeCCIFingerprint {

    // MARK: Signed app identity

    /// The Android OneApp build the gate validates the signature against.
    /// The signature covers these, so they must match the constants below.
    static let clientVersion = "1.4.0"
    static let osCode = "android"
    static let osVersion = "14"
    static let deviceModel = "SM-S918B"
    static let notificationProvider = "FCM"
    static let userAgent = "okhttp/4.12.0"
    static let region = "eu"

    /// The gate's own rejection codes. Only these send a call to the legacy
    /// route; anything else (9013 invalid code, 9030 expired, a 5xx) is a
    /// real answer from the signed path.
    static let gateRejectionCodes: Set<Int> = [9035, 9036, 9037]

    // MARK: Signing

    private static let identityHeaders = ["client-id", "client-name", "client-version", "client-os-code"]

    /// What Java's `\s` matches without Unicode mode, and Python's under
    /// `re.ASCII`: space, tab, LF, VT, FF, CR.
    private static let asciiWhitespace = Set(" \t\n\u{0B}\u{0C}\r".unicodeScalars)

    /// HMAC-SHA256, lower-case hex.
    ///
    /// Key: client-id + client-name + client-version + client-os-code, then
    /// the brand's three secret pieces. Message: the same four, then
    /// client-os-version, X-Timestamp and the request body with ASCII
    /// whitespace removed.
    static func signature(headers: [String: String], keyPieces: [String], body: String = "") -> String {
        var lower: [String: String] = [:]
        for (key, value) in headers { lower[key.lowercased()] = value }
        let identity = identityHeaders.map { lower[$0] ?? "" }.joined()
        // Unicode scalars, not Characters: "\r\n" is a single Character.
        let stripped = String(String.UnicodeScalarView(
            body.unicodeScalars.filter { !asciiWhitespace.contains($0) }
        ))
        let message = identity + (lower["client-os-version"] ?? "") + (lower["x-timestamp"] ?? "") + stripped
        let key = SymmetricKey(data: Data((identity + keyPieces.joined()).utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// The full header set for a signed call, X-Timestamp and X-Fingerprint
    /// included. `body` must be exactly what is sent.
    static func headers(
        config: EuropeCCIConfig,
        deviceId: String,
        timezone: String,
        body: String = "",
        now: Date = Date()
    ) -> [String: String] {
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).uppercased()
        var headers: [String: String] = [
            "client-id": config.packageId,
            "client-name": config.signedClientName,
            "client-version": clientVersion,
            "client-os-code": osCode,
            "client-os-version": osVersion,
            "client-device-id": deviceId,
            "client-device-model": deviceModel,
            "client-notification-provider-type": notificationProvider,
            "locale": "EN",
            "timezone": timezone,
            "App-Request-Id": "\(requestId)_\(deviceId.replacingOccurrences(of: "-", with: ""))_AOS",
            "X-Brand": config.brandLabel,
            "X-Region": region,
            "User-Agent": userAgent,
            "Accept": "*/*",
            "Accept-Language": "en",
            "X-Timestamp": String(Int64(now.timeIntervalSince1970 * 1000))
        ]
        headers["X-Fingerprint"] = signature(headers: headers, keyPieces: config.fingerprintKey, body: body)
        return headers
    }

    /// The gate code in a thrown 4xx, or nil when it's any other failure.
    static func gateRejection(in error: Error) -> Int? {
        guard let error = error as? APIError,
              let status = error.code, (400..<500).contains(status),
              let body = error.userInfo?["responseBody"]?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let code = json["code"] as? Int,
              gateRejectionCodes.contains(code) else { return nil }
        return code
    }
}
