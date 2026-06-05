//
//  HyundaiCanada.swift
//  BetterBlueKit
//
//  Hyundai Canada shared helpers
//

import Foundation

extension HyundaiCanadaAPIClient {

    // MARK: - Headers

    func headers() -> [String: String] {
        [
            "client_id": clientId,
            "client_secret": clientSecret,
            "Host": apiHost,
            "deviceid": deviceId,
            // "CWP" (Connected Web Portal), not "SPA" (native app): the
            // CA MFA endpoints only honor the web-portal client. See the
            // userAgent note in HyundaiCanadaAPIClient.
            "from": "CWP",
            "language": "0",
            "offset": timezoneOffsetHeader,
            "User-Agent": userAgent,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "origin": "https://\(apiHost)",
            "referer": "https://\(apiHost)/login"
        ]
    }

    func authorizedHeaders(
        authToken: AuthToken,
        vehicleId: String? = nil,
        pAuth: String? = nil
    ) -> [String: String] {
        var result = headers()
        result["Accesstoken"] = authToken.accessToken

        if let vehicleId {
            result["Vehicleid"] = vehicleId
        }
        if let pAuth {
            result["Pauth"] = pAuth
        }
        if let cookie = cloudFlareCookie {
            result["Cookie"] = cookie
        }

        return result
    }

    func commandStatusHeaders(
        authToken: AuthToken,
        vehicleId: String,
        pAuth: String,
        transactionId: String
    ) -> [String: String] {
        var result = authorizedHeaders(authToken: authToken, vehicleId: vehicleId, pAuth: pAuth)
        result["TransactionId"] = transactionId
        return result
    }

    // MARK: - Cloudflare Cookie

    /// Attempts to fetch the Cloudflare `__cf_bm` bot-management cookie by
    /// loading the login page. Returns the cookie string if found, or `nil`
    /// if Cloudflare is not enforcing it (the server now sets it via JS rather
    /// than a `Set-Cookie` header, so native HTTP clients may not receive it).
    func fetchCloudFlareCookie() async throws -> String? {
        let loginURL = URL(string: "https://\(apiHost)/login")!

        let (_, response) = try await performRequest(
            url: loginURL.absoluteString,
            method: .GET,
            headers: headers(),
            requestType: .login
        )

        // Primary: parse Set-Cookie headers from the final response.
        if let cookie = HTTPCookie.cookies(
            withResponseHeaderFields: extractResponseHeaders(from: response),
            for: loginURL
        ).first(where: { $0.name.lowercased() == "__cf_bm" }) {
            return "__cf_bm=\(cookie.value)"
        }

        // Fallback: URLSession stores cookies from all responses in the redirect
        // chain into HTTPCookieStorage.shared; check there too.
        if let cookie = HTTPCookieStorage.shared.cookies(for: loginURL)?
            .first(where: { $0.name.lowercased() == "__cf_bm" }) {
            return "__cf_bm=\(cookie.value)"
        }

        // Cookie not present — Cloudflare may be enforcing via JS challenge only.
        // Log a warning and let the caller proceed; the POST login will surface
        // any actual rejection from the server.
        BBLogger.warning(.auth, "HyundaiCanada: __cf_bm cookie not found in login page response — proceeding without it")
        return nil
    }

    // MARK: - Shared Response Parser

    func parseCanadaResponse(_ data: Data, context: String) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.logError(
                "Invalid JSON in Canada \(context) response",
                apiName: apiName
            )
        }

        guard let responseHeader = json["responseHeader"] as? [String: Any] else {
            throw APIError.logError(
                "Missing responseHeader in Canada \(context) response",
                apiName: apiName
            )
        }

        if isCanadaResponseSuccess(responseHeader["responseCode"]) {
            return json
        }

        let error = json["error"] as? [String: Any]
        let errorCode = error?["errorCode"] as? String
        let errorDesc = (error?["errorDesc"] as? String) ?? "Unknown Canada API error: \(json)"
        let lower = errorDesc.lowercased()

        if lower.contains("expired") || lower.contains("deleted") || lower.contains("ip validation") {
            throw APIError.invalidCredentials(errorDesc, apiName: apiName)
        }

        // 6533: Bluelink is already processing a prior request for this vehicle
        if errorCode == "6533" || lower.contains("processing an earlier inquiry") {
            throw APIError.concurrentRequest(errorDesc, apiName: apiName)
        }

        throw APIError.logError("Canada \(context) failed: \(errorDesc)", apiName: apiName)
    }

    /// Hyundai Canada's `responseCode` field has been observed in three
    /// shapes: integer (`0`/`1`), string (`"0"`/`"1"`), and most
    /// recently — as of mid-2026 — JSON boolean (`false`/`true`).
    /// Boolean values are inverted: `false` means success, `true` means
    /// failure (matching the `responseDesc: "Success"` / `"Failure"`
    /// strings the same field carries).
    func isCanadaResponseSuccess(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool == false }
        if let int = value as? Int { return int == 0 }
        if let string = value as? String { return string == "0" || string.lowercased() == "false" }
        return false
    }

    private var timezoneOffsetHeader: String {
        let hours = TimeZone.current.secondsFromGMT() / 3600
        return String(format: "%+03d", hours)
    }
}
