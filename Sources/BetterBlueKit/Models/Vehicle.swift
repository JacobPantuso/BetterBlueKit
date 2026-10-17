//
//  Vehicle.swift
//  BetterBlueKit
//
//  Vehicle model definitions
//

import Foundation

// MARK: - Vehicle Models

public struct Vehicle: Codable, Identifiable, Equatable, Sendable {
    public var id: String { vin }
    public var regId: String, vin: String, model: String
    public var accountId: UUID, fuelType: FuelType
    public var generation: Int, odometer: Distance, vehicleKey: String?
    public var marketOptions: VehicleMarketOptions?
    /// Model year, where the API reports one (Hyundai Canada's `vhcllst`
    /// does). Canada's HVAC temperature scale changed with MY2020, so
    /// the climate codec needs it; nil means unknown and decodes with
    /// the pre-2020 scale, matching hyundai_kia_connect_api's default.
    public var modelYear: Int?
    /// The manufacturer's paint code, e.g. "A2B" (Abyss Black). Canada's
    /// vehicle list sends it as `exteriorColor`, Europe's as
    /// `detailInfo.outColor`; nil where the region doesn't report one.
    public var exteriorColorCode: String?
    /// The model as the manufacturer names it ("IONIQ 6 EV", "EV9"), not the
    /// owner's nickname, which is what `model` holds. Canada's vehicle list
    /// sends it as `modelName`, Europe's as `detailInfo.saleCarmdlEnNm`.
    public var modelName: String?

    // Optional fields populated from the vehicle list endpoint
    public var trim: String?
    public var preConditioningOption: Int?  // 1 = supported
    public var mileageForNextService: Double?  // km
    public var nextServiceDate: String?  // "YYYYMMDD" format
    public var webManualUrl: String?

    public init(vin: String, regId: String, model: String, accountId: UUID,
                fuelType: FuelType, generation: Int, odometer: Distance, vehicleKey: String? = nil,
                marketOptions: VehicleMarketOptions = .generic,
                trim: String? = nil, preConditioningOption: Int? = nil,
                mileageForNextService: Double? = nil, nextServiceDate: String? = nil,
                webManualUrl: String? = nil, modelYear: Int? = nil,
                exteriorColorCode: String? = nil, modelName: String? = nil) {
        (self.vin, self.regId, self.model, self.accountId) = (vin, regId, model, accountId)
        (self.fuelType, self.generation, self.odometer, self.vehicleKey) =
            (fuelType, generation, odometer, vehicleKey)
        self.marketOptions = marketOptions
        self.trim = trim
        self.preConditioningOption = preConditioningOption
        self.mileageForNextService = mileageForNextService
        self.nextServiceDate = nextServiceDate
        self.webManualUrl = webManualUrl
        self.modelYear = modelYear
        self.exteriorColorCode = exteriorColorCode
        self.modelName = modelName
    }
}
