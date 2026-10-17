//
//  HyEuLockStatusTests.swift
//  BetterBlueKit
//
//  A real ccs2 status from a 2026 IONIQ 6 in Europe (2026-10-17), trimmed to
//  the fields the parser reads. MyHyundai showed the car closed and locked
//  while every door's `Lock` was 0.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Hyundai EU lock status")
struct HyEuLockStatusTests {
    static let locked2026Ioniq6 = """
    {"retCode":"S","resCode":"0000","resMsg":{"resCode":"0000","ServiceNo":"RVS-K","RetCode":"S","lastUpdateTime":"1792243156050","state":{"Vehicle":{"Body":{"Hood":{"Frunk":{"Fault":0},"Open":0},"Trunk":{"Open":0}},"Cabin":{"Window":{"Row1":{"Driver":{"Open":0,"OpenLevel":0},"Passenger":{"Open":0,"OpenLevel":0}},"Row2":{"Left":{"Open":0,"OpenLevel":0},"Right":{"Open":0,"OpenLevel":0}}},"SteeringWheel":{"Heat":{"RemoteControl":{"Step":0},"State":0}},"HVAC":{"Row1":{"Driver":{"Temperature":{"Value":"OFF","Unit":0},"Blower":{"SpeedLevel":0}}},"Temperature":{"RangeType":1}},"Door":{"Row1":{"Driver":{"Open":0,"Lock":0},"Passenger":{"Open":0,"Lock":0}},"Row2":{"Left":{"Open":0,"Lock":0},"Right":{"Open":0,"Lock":0}}}},"Drivetrain":{"FuelSystem":{"DTE":{"Unit":1,"Total":377},"LowFuelWarning":0,"FuelLevel":0},"Odometer":11590.5,"Transmission":{"ParkingPosition":1,"GearPosition":0}},"Electronics":{"Battery":{"Level":79},"PowerSupply":{"Accessory":0,"Ignition3":0,"Ignition1":0}},"Green":{"DrivingReady":0,"BatteryManagement":{"BatteryRemain":{"Value":201722.4,"Ratio":74.5,"Unit":"kJ"},"BatteryCapacity":{"Value":302400,"Unit":"kJ"}},"ChargingInformation":{"Charging":{"SoC":{"Decimal":0.4,"Raw":73},"RemainTime":0},"ConnectorFastening":{"State":0},"TargetSoC":{"Standard":80,"Quick":80}},"Electric":{"SmartGrid":{"RealTimePower":0}},"ChargingDoor":{"State":2,"ErrorState":1}},"DrivingReady":0,"Version":"CCU2026101713191402","Date":"20261017131914.000","Offset":"2"}}},"msgId":"64d3d7a0-ca2d-11f1-9a34-d4598b0eb52c"}
    """

    @Test("Lock 0 on every door reads as locked, as upstream reads it")
    @MainActor func lockZeroIsLocked() throws {
        let client = HyundaiEuropeAPIClient(configuration: APIClientConfiguration(
            region: .europe, brand: .hyundai, username: "u", password: "p", pin: "0000",
            accountId: UUID(), deviceId: UUID().uuidString))
        let vehicles = try client.parseVehiclesResponse(Data(HyEuSampleJSON.vehiclesList.utf8))
        let ccs2 = try #require(vehicles.first { $0.marketOptions?.ccs2Supported == true })
        let status = try client.parseVehicleStatusResponse(Data(Self.locked2026Ioniq6.utf8), Data(HyEuSampleJSON.parkResponse.utf8), for: ccs2)
        #expect(status.lockStatus == .locked)
    }
}
