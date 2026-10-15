//
//  VehiclePaintCodeTests.swift
//  BetterBlueKit
//
//  The paint code and model year from each region's vehicle list, which the
//  app uses to draw the owner's car in its real colour and body style.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Vehicle Paint Code")
struct VehiclePaintCodeTests {

    @Test("Canada reads exteriorColor and modelYear")
    @MainActor func testCanada() throws {
        // Shape of a real Hyundai Canada vhcllst entry (2024 IONIQ 6), trimmed.
        let json = """
        {"responseHeader":{"responseCode":0,"responseDesc":"Success"},"result":{"vehicles":[
          {"vehicleId":"ID1","nickName":"IONIQ","modelCode":"I614EAEME2AV","modelName":"IONIQ 6 EV",
           "modelYear":"2024","fuelKindCode":"E","trim":"Preferred Ult Pkg","exteriorColor":"A2B",
           "vehicleKindCode":"I6","genType":"G3","vin":"KMH00000000005930"}]}}
        """
        let client = HyundaiCanadaAPIClient(configuration: APIClientConfiguration(
            region: .canada, brand: .hyundai, username: "u", password: "p", pin: "1234", accountId: UUID()))
        let vehicle = try #require(try client.parseCanadaVehiclesResponse(Data(json.utf8)).first)
        #expect(vehicle.exteriorColorCode == "A2B")
        #expect(vehicle.modelYear == 2024)
    }

    @Test("Europe reads detailInfo.outColor and year")
    @MainActor func testEurope() throws {
        let client = HyundaiEuropeAPIClient(configuration: APIClientConfiguration(
            region: .europe, brand: .hyundai, username: "u", password: "p", pin: "0000",
            accountId: UUID(), deviceId: UUID().uuidString))
        let vehicles = try client.parseVehiclesResponse(Data(HyEuSampleJSON.vehiclesList.utf8))
        #expect(vehicles.map(\.exteriorColorCode) == ["M9U", "R2P"])
        #expect(vehicles.map(\.modelYear) == [2022, 2025])
    }
}
