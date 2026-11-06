//
//  HyundaiCanada+Chargers.swift
//  BetterBlueKit
//
//  Hyundai Canada charging-station search (`iac/csList`).
//

import Foundation

extension HyundaiCanadaAPIClient {

    public func fetchChargeStations(
        near coordinate: (latitude: Double, longitude: Double),
        radiusKm: Int,
        authToken: AuthToken,
        for vehicle: Vehicle
    ) async throws -> [ChargeStationInfo] {
        _ = try await ensureCloudFlareCookie()

        // The Android app calls `iac/serviceInfo` before searching: it primes
        // the in-app-charging session and reports station-search entitlement.
        // It was never shown to be needed, so it is kept but sent once per
        // client instance, and stays best-effort.
        let clientKey = ObjectIdentifier(self)
        if !Self.serviceInfoSent.contains(clientKey) {
            Self.serviceInfoSent.insert(clientKey)
            do {
                _ = try await performJSONRequest(
                    url: "\(apiBaseURL)/iac/serviceInfo",
                    method: .POST,
                    headers: iacHeaders(authToken: authToken, vehicleId: vehicle.regId),
                    body: ["vehicleInfo": [
                        "modelCode": "",
                        "modelYear": vehicle.modelYear.map(String.init) ?? "",
                        "brand": "H"
                    ]],
                    requestType: .fetchChargeStations,
                    vin: vehicle.vin
                )
            } catch {
                // Ignore: csList still runs regardless.
            }
        }

        // Match the official app's runtime call: it omits `chargingSpeeds`
        // entirely (its own note says the server's speed filter isn't
        // reliable) and searches a ~15 km radius. The build where csList
        // started working both dropped `chargingSpeeds` and raised the radius
        // from 5 to at least 15 km at the same time, so which change mattered
        // is unknown; both are kept.
        let body: [String: Any] = [
            "country": "CA",
            "coordinate": ["lat": coordinate.latitude, "lon": coordinate.longitude],
            "radius": max(radiusKm, 15),
            "radiusUnit": "km",
            "language": "en",
            "size": 100,
            "page": 0
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await performRequest(
            url: "\(apiBaseURL)/iac/csList",
            method: .POST,
            headers: iacHeaders(authToken: authToken, vehicleId: vehicle.regId),
            body: bodyData,
            requestType: .fetchChargeStations,
            vin: vehicle.vin
        )

        // JSON parse, station parse and sort run off the main actor: the
        // response is large.
        return await Task.detached(priority: .userInitiated) {
            HyundaiCanadaAPIClient.parseChargeStations(from: data)
        }.value
    }

    /// Tracks which client instances have already sent `iac/serviceInfo`.
    private static var serviceInfoSent = Set<ObjectIdentifier>()

    nonisolated static func parseChargeStations(from data: Data) -> [ChargeStationInfo] {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        // A missing or malformed array means "nothing nearby", not a failure:
        // the transport already succeeded.
        let result = json["result"] as? [String: Any]
        let raw = result?["chargingStations"] as? [[String: Any]] ?? []
        return raw.compactMap(parseChargeStation).sorted {
            switch ($0.distanceKm, $1.distanceKm) {
            case let (lhs?, rhs?): lhs < rhs
            case (_?, nil): true
            default: false
            }
        }
    }

    // MARK: - Parsing

    nonisolated private static func parseChargeStation(_ station: [String: Any]) -> ChargeStationInfo? {
        let coordinates = station["coordinates"] as? [String: Any]
        let center = coordinates?["center"] as? [String: Any]
        let guidance = coordinates?["guidance"] as? [String: Any]

        guard let id = chargerString(station["id"]) ?? chargerString(station["poiId"]),
              let lat = chargerDouble(center?["lat"]) ?? chargerDouble(guidance?["lat"]),
              let lon = chargerDouble(center?["lon"]) ?? chargerDouble(guidance?["lon"])
        else { return nil }

        let data = chargerLanguageData(station["languageResources"], key: "language") ?? [:]
        let operation = ((data["providers"] as? [String: Any])?["operation"] as? [[String: Any]])?.first

        let connectors = (station["chargers"] as? [[String: Any]] ?? [])
            .flatMap { $0["connectors"] as? [[String: Any]] ?? [] }
        var types: [String] = []
        for type in connectors.flatMap({ $0["connectorTypes"] as? [String] ?? [] }) where !types.contains(type) {
            types.append(type)
        }

        let topPower = chargerDouble(station["chargingPower"])
        let connectorPower = connectors.compactMap { chargerDouble($0["chargingPower"]) }.max()
        let maxPower = (topPower ?? 0) > 0 ? topPower : connectorPower

        let statuses = station["status"] as? [[String: Any]] ?? []
        return ChargeStationInfo(
            id: id,
            name: data["name"] as? String ?? "",
            address: data["address"] as? String,
            network: operation?["name"] as? String ?? operation?["brandName"] as? String,
            networkId: operation.flatMap { chargerString($0["id"]) },
            latitude: lat,
            longitude: lon,
            distanceKm: chargerDouble(station["distance"]),
            maxPowerKW: maxPower,
            availableConnectors: statuses.reduce(0) { $0 + (chargerInt($1["numberOfAvailableConnectors"]) ?? 0) },
            totalConnectors: statuses.reduce(0) { $0 + (chargerInt($1["numberOfConnectors"]) ?? 0) },
            connectorTypes: types,
            price: chargerPrice(station)
        )
    }

    nonisolated private static func chargerPrice(_ station: [String: Any]) -> String? {
        let tariff = (station["tariff"] as? [[String: Any]])?.first
        if let text = chargerLanguageData(tariff?["tariffAltText"], key: "lang")?["text"] as? String,
           !text.trimmingCharacters(in: .whitespaces).isEmpty {
            return text
        }
        let fee = ((station["chargers"] as? [[String: Any]])?.first)?["chargingFee"] as? String
        guard let fee, !fee.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return fee
    }

    /// Picks the English entry (else the first) from a localized array. The
    /// payload nests the fields under `data` for station resources but puts
    /// `text` directly on tariff entries, so a missing `data` falls back to
    /// the entry itself.
    nonisolated private static func chargerLanguageData(_ value: Any?, key: String) -> [String: Any]? {
        guard let entries = value as? [[String: Any]] else { return nil }
        let entry = entries.first { (($0[key] as? String) ?? "").lowercased().hasPrefix("en") } ?? entries.first
        return entry.map { ($0["data"] as? [String: Any]) ?? $0 }
    }

    nonisolated private static func chargerDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return (value as? String).flatMap(Double.init)
    }

    nonisolated private static func chargerInt(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return (value as? String).flatMap(Int.init)
    }

    nonisolated private static func chargerString(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
