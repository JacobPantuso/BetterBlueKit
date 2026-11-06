//
//  ChargeStationInfo.swift
//  BetterBlueKit
//
//  A public charging station near a coordinate, as reported by a
//  manufacturer's station-search endpoint.
//

import Foundation

public struct ChargeStationInfo: Sendable, Equatable {
    public let id: String
    public let name: String
    public let address: String?
    public let network: String?
    public let networkId: String?
    public let latitude: Double
    public let longitude: Double
    public let distanceKm: Double?
    public let maxPowerKW: Double?
    public let availableConnectors: Int?
    public let totalConnectors: Int?
    public let connectorTypes: [String]
    public let price: String?

    public init(
        id: String,
        name: String,
        address: String? = nil,
        network: String? = nil,
        networkId: String? = nil,
        latitude: Double,
        longitude: Double,
        distanceKm: Double? = nil,
        maxPowerKW: Double? = nil,
        availableConnectors: Int? = nil,
        totalConnectors: Int? = nil,
        connectorTypes: [String] = [],
        price: String? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.network = network
        self.networkId = networkId
        self.latitude = latitude
        self.longitude = longitude
        self.distanceKm = distanceKm
        self.maxPowerKW = maxPowerKW
        self.availableConnectors = availableConnectors
        self.totalConnectors = totalConnectors
        self.connectorTypes = connectorTypes
        self.price = price
    }

    /// Hyundai tags Tesla's network with operator id "258D"; the name check
    /// catches stations where the operator id is missing but the name isn't.
    public var isTesla: Bool {
        networkId == "258D" || (network?.range(of: "tesla", options: .caseInsensitive) != nil)
    }
}
