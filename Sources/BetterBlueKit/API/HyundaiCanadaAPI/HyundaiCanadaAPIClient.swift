//
//  HyundaiCanadaAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Canada API Client
//

import Foundation

// MARK: - Hyundai Canada API Client

@MainActor
public final class HyundaiCanadaAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    let clientId = "HATAHSPACA0232141ED9722C67715A0B"
    let clientSecret = "CLISCR01AHSPA"
    // DO NOT revert to a native-app User-Agent. Hyundai Canada sits
    // behind Cloudflare: the `/login` GET we use to mint the `__cf_bm`
    // cookie (see `fetchCloudFlareCookie`) only returns that cookie for
    // a browser-like client. With the old `MyHyundai/… iOS` UA + `from:
    // SPA`, Cloudflare instead serves a JS-challenge HTML page, no
    // `__cf_bm` is set, and EVERY request fails with "CloudFlare cookie
    // missing from login response" (GitHub #67). The browser UA + `from:
    // CWP` (the web-portal identity, matching the hyundai_kia_connect_api
    // reference, KiaUvoApiCA.py) gets the cookie and also reaches the
    // web-portal MFA endpoints. 2026.5.14 shipped this and worked;
    // 2026.5.15 reverted it and broke CA again — hence this is restored.
    let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Stable per-account device ID. Hyundai Canada's anti-fraud
    /// challenge fires every time a "new device" logs in — using a
    /// fresh random UUID per session guarantees the user sees an OTP
    /// challenge (errorCode 7110) on every login. `BBAccount` already
    /// generates and persists a stable UUID per account; honor that
    /// when present, fall back to a random UUID only if the host
    /// didn't supply one (e.g. bbcli without a stored config).
    /// (Matches the hyundai_kia_connect_api Python reference, which
    /// derives a deterministic device ID from MAC + hostname for the
    /// same reason.)
    lazy var deviceId: String = configuration.deviceId ?? UUID().uuidString.uppercased()

    // Note: temperature lookup tables removed in the EU temperature
    // cleanup — the canonical Standard table now lives on
    // `Temperature` (see `Models/Measurements.swift`), and the HEX
    // encoding goes through `Temperature.encodeAirTempToHEX`.

    var cloudFlareCookie: String?

    // MARK: - MFA Flow State
    //
    // Hyundai Canada's MFA differs slightly from Kia USA's: the OTP key
    // is only issued AFTER the user picks email/SMS (Kia returns it in
    // the initial challenge). We stash everything we learn at each step
    // here so the protocol's three-method MFA contract still works.
    /// `userInfoUuid` returned by `mfa/selverifmeth`. Surfaced as `xid`
    /// in the `requiresMFA` error and threaded through every later call.
    var mfaUserInfoUuid: String?
    /// Email associated with the account, returned by `selverifmeth` and
    /// echoed back by `sendotp` / `genmfatkn`.
    var mfaEmail: String?
    /// `otpKey` returned by `mfa/sendotp`, consumed by `mfa/validateotp`.
    var mfaOtpKey: String?
    /// Last-4 (or full, depending on server) of the SMS number echoed
    /// by `selverifmeth`. Threaded back into `sendotp` for the SMS
    /// delivery path.
    var mfaPhone: String?
    /// Final auth token built from `mfa/genmfatkn`'s response. Returned
    /// from `completeMFALogin` so the caller never sees the multi-step
    /// dance under the hood.
    var mfaCompletedAuthToken: AuthToken?

    // Kia Canada runs the same `/tods/api` service as Hyundai Canada, at
    // kiaconnect.ca instead of mybluelink.ca (the hyundai_kia_connect_api
    // reference drives both with one class), so this client serves both brands.
    var baseURL: String { region.apiBaseURL(for: brand == .kia ? .kia : .hyundai) }
    var apiBaseURL: String { "\(baseURL)/tods/api" }
    var apiHost: String { brand == .kia ? "kiaconnect.ca" : "mybluelink.ca" }

    public override var apiName: String { brand == .kia ? "KiaCanada" : "HyundaiCanada" }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiCanada: starting login")

        let cookie = try await ensureCloudFlareCookie()

        var loginHeaders = headers()
        if let cookie { loginHeaders["Cookie"] = cookie }

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/v2/login",
            method: .POST,
            headers: loginHeaders,
            body: [
                "loginId": username,
                "password": password
            ],
            requestType: .login
        )

        // Intercept the OTP-required response (errorCode 7110) before
        // the generic parser runs — it would otherwise throw a generic
        // "Canada login failed" error and the caller couldn't tell
        // that an MFA challenge is what's needed. `beginMFAFlow` always
        // throws `requiresMFA` on success; control only returns here on
        // a non-7110 response, which the regular parser handles.
        if isOTPRequiredResponse(data) {
            try await beginMFAFlow(cookie: cookie ?? "")
        }

        return try parseCanadaLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        _ = try await ensureCloudFlareCookie()

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vhcllst",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseCanadaVehiclesResponse(data)
    }

    // Cached (sltvhcl) vs real-time (rltmvhclsts) status. Real-time wakes
    // the vehicle modem; use sparingly.
    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        try await fetchVehicleStatus(for: vehicle, authToken: authToken, cached: cached, includeLocation: true)
    }

    // Overload that allows skipping location injection
    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool,
        includeLocation: Bool
    ) async throws -> VehicleStatus {
        _ = try await ensureCloudFlareCookie()

        let statusEndpoint = cached ? "sltvhcl" : "rltmvhclsts"
        let (primaryData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(statusEndpoint)",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: ["vehicleId": vehicle.regId],
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )
        if !cached {
            do {
                _ = try parseCanadaResponse(primaryData, context: "status")
            } catch let error as APIError where error.errorType == .concurrentRequest {
                throw error
            } catch {
                BBLogger.debug(.api, "HyundaiCanada: realtime status error, falling back to cached payload: \(error)")
            }
        }

        let statusData = cached ? primaryData : try await fetchRealtimeStatusData(
            primaryData: primaryData,
            vehicle: vehicle,
            authToken: authToken
        )
        let finalData = includeLocation
            ? try await injectLocationCoordinates(into: statusData, vehicle: vehicle, authToken: authToken)
            : statusData

        do {
            return try parseCanadaVehicleStatusResponse(finalData, for: vehicle)
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: parsing final status payload failed: \(error)")
            return try parseCanadaVehicleStatusResponse(primaryData, for: vehicle)
        }
    }

    private func fetchRealtimeStatusData(
        primaryData: Data,
        vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> Data {
        // Fetch cached sltvhcl payload for complete vehicle metadata
        var finalData = primaryData
        do {
            let (cachedData, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/sltvhcl",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
                body: ["vehicleId": vehicle.regId],
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
            finalData = cachedData
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed fetching sltvhcl: \(error)")
        }

        return finalData
    }

    private func injectLocationCoordinates(into data: Data, vehicle: Vehicle, authToken: AuthToken) async throws -> Data {
        do {
            let pAuth = try await fetchCommandAuthCode(authToken: authToken)

            // fndmcr returns 6533 when the car's modem is still processing a prior request.
            // fetchLocationWithRetry parses the response inside the loop so the .concurrentRequest
            // error is actually caught and retried (parsing is where the 6533 is detected).
            let location = try await fetchLocationWithRetry(
                vehicle: vehicle,
                authToken: authToken,
                pAuth: pAuth
            )

            guard var finalJson = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return data
            }

            let coord: [String: Any] = ["lat": location.latitude, "lon": location.longitude]
            var result = finalJson["result"] as? [String: Any] ?? [:]
            var status = result["status"] as? [String: Any]
                ?? result["vehicleStatus"] as? [String: Any] ?? [:]
            status["coord"] = coord
            status["vehicleLocation"] = ["coord": coord]
            result["status"] = status
            finalJson["result"] = result
            return try JSONSerialization.data(withJSONObject: finalJson)
        } catch let error as APIError where error.errorType == .concurrentRequest {
            throw error
        } catch {
            BBLogger.debug(.api, "HyundaiCanada: failed injecting location: \(error)")
            return data
        }
    }

    private func fetchLocationWithRetry(
        vehicle: Vehicle,
        authToken: AuthToken,
        pAuth: String,
        maxAttempts: Int = 3,
        retryDelayNanoseconds: UInt64 = 4_000_000_000
    ) async throws -> VehicleStatus.Location {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                BBLogger.debug(.api, "HyundaiCanada: fndmcr retry \(attempt)/\(maxAttempts - 1) — concurrent request, waiting \(retryDelayNanoseconds / 1_000_000_000)s")
                try await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
            do {
                // Append ?retry=N on retries so the HTTP log shows each attempt distinctly.
                let url = attempt == 0
                    ? "\(apiBaseURL)/evc/fme"
                    : "\(apiBaseURL)/evc/fme?retry=\(attempt)"
                let (locationData, _, _) = try await performJSONRequest(
                    url: url,
                    method: .POST,
                    headers: spaLocationHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: pAuth),
                    body: ["pin": pin],
                    requestType: .fetchVehicleStatus,
                    vin: vehicle.vin
                )
                // Parse inside the loop — the 6533 is in the JSON body (HTTP 200),
                // so the throw only happens here, not in performJSONRequest.
                return try parseCanadaLocationResponse(locationData)
            } catch let error as APIError where error.errorType == .concurrentRequest {
                BBLogger.debug(.api, "HyundaiCanada: fndmcr attempt \(attempt + 1) got concurrent request error")
                lastError = error
            }
        }
        throw lastError ?? APIError.logError("fndmcr failed after \(maxAttempts) attempts", apiName: apiName)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        _ = try await ensureCloudFlareCookie()

        let authCode = try await fetchCommandAuthCode(authToken: authToken)

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode
        )
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }

    public func fetchLocationOnly(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus.Location {
        _ = try await ensureCloudFlareCookie()
        let pAuth = try await fetchCommandAuthCode(authToken: authToken)
        return try await fetchLocationWithRetry(vehicle: vehicle, authToken: authToken, pAuth: pAuth)
    }

    public func fetchSurroundView(for vehicle: Vehicle, authToken: AuthToken, cached: Bool = true) async throws -> SVMResult {
        _ = try await ensureCloudFlareCookie()

        guard !cached else {
            return try await fetchLastSurroundView(vehicle: vehicle, authToken: authToken)
        }

        // The newest capture already on the server, so the poll below can tell
        // a fresh one from it.
        let previousTime = (try? await fetchLastSurroundView(vehicle: vehicle, authToken: authToken))?
            .svmLocations?.first?.utcTime

        // Sent exactly as the MyHyundai app sends it (Proxyman, 2026-09-26):
        // SPA headers, no PIN, no pauth, empty body. Treating it as a
        // PIN-authorised remote command — vrfypin, a Pauth header and a
        // {"vehicleId"} body — is what the server rejected with error 6459.
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/rfc/fndmcrsvm",
            method: .POST,
            headers: spaLocationHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: nil),
            requestType: .sendCommand,
            vin: vehicle.vin
        )
        try validateCommandResponse(data, context: "surround view request")

        // The response carries no TransactionId to poll /rmtsts with: the app
        // is told by push when the car has uploaded, which a third-party client
        // can't receive. So poll the cloud-side result — cheap, it doesn't wake
        // the car the way rltmvhcsts does — until a capture newer than the one
        // above appears. The car typically takes about two minutes.
        try await Task.sleep(nanoseconds: 20_000_000_000)
        for _ in 0..<28 { // 20 s + 28 × 10 s ≈ 5 minutes
            if let latest = try? await fetchLastSurroundView(vehicle: vehicle, authToken: authToken),
               let time = latest.svmLocations?.first?.utcTime,
               time != previousTime {
                return latest
            }
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        throw APIError.logError("Surround view capture timed out after 5 minutes", apiName: apiName)
    }

    private func fetchLastSurroundView(vehicle: Vehicle, authToken: AuthToken) async throws -> SVMResult {
        let (imgData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/rfc/lastmcrsvm",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: ["vehicleId": vehicle.regId],
            requestType: .fetchVehicleStatus
        )
        return try parseSurroundViewResponse(imgData)
    }

    private func parseSurroundViewResponse(_ data: Data) throws -> SVMResult {
        let response = try JSONDecoder().decode(SVMResponse.self, from: data)
        guard let result = response.result else {
            throw APIError.serverError("Invalid surround view response format", apiName: apiName)
        }
        return result
    }

    // MARK: - Command Flow

    private func fetchCommandAuthCode(authToken: AuthToken) async throws -> String {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/vrfypin",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            body: ["pin": pin],
            requestType: .sendCommand
        )

        return try parseCommandAuthResponse(data)
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String
    ) async throws {
        if case .startClimate = command {
            do {
                try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: false
                )
                return
            } catch {
                try await sendCommandRequest(
                    for: vehicle,
                    command: command,
                    authToken: authToken,
                    authCode: authCode,
                    useRemoteControl: true
                )
                return
            }
        }

        try await sendCommandRequest(
            for: vehicle,
            command: command,
            authToken: authToken,
            authCode: authCode,
            useRemoteControl: false
        )
    }

    private func sendCommandRequest(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
        authCode: String,
        useRemoteControl: Bool
    ) async throws {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/\(commandPath(for: command))",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleId: vehicle.regId, pAuth: authCode),
            body: makeCommandBody(command: command, useRemoteControl: useRemoteControl),
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        try validateCommandResponse(data, context: "command")
    }

    private func pollForCommandCompletion(
        vehicle: Vehicle,
        authToken: AuthToken,
        authCode: String,
        transactionId: String,
        initialDelayNanoseconds: UInt64 = 0
    ) async throws {
        if initialDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: initialDelayNanoseconds)
        }

        var attempts = 0
        var lastKnownResult = "unknown"

        while attempts <= 30 {
            let (data, _, _) = try await performJSONRequest(
                url: "\(apiBaseURL)/rmtsts",
                method: .POST,
                headers: commandStatusHeaders(
                    authToken: authToken,
                    vehicleId: vehicle.regId,
                    pAuth: authCode,
                    transactionId: transactionId
                ),
                requestType: .sendCommand
            )

            let pollResult = try commandPollResult(data)
            lastKnownResult = pollResult

            if isSuccessfulPollResult(pollResult) {
                return
            }
            if isFailedPollResult(pollResult) {
                throw APIError.logError("Canada command failed (\(pollResult))", apiName: apiName)
            }

            attempts += 1
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        throw APIError.logError(
            "Canada command completion polling timed out (last result: \(lastKnownResult))",
            apiName: apiName
        )
    }

    private func ensureCloudFlareCookie() async throws -> String? {
        if let cloudFlareCookie, !cloudFlareCookie.isEmpty {
            return cloudFlareCookie
        }

        let cookie = try await fetchCloudFlareCookie()
        cloudFlareCookie = cookie
        return cookie
    }
}
