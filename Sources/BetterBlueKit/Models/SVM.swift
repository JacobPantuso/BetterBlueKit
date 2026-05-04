//
//  SVM.swift
//  BetterBlueKit
//
//  Surround View Monitor data models
//

import Foundation

public struct SVMResult: Codable {
    public let svmLocations: [SVMLocation]?
}

public struct SVMLocation: Codable {
    public let gpsDetail: SVMGPSDetail?
    public let svmImage: String?
    public let validAngleofView: [Double]?
    public let boundaryArea: [Int]?
    public let installAngle: [Double]?
    public let sidemirrorOpen: Bool?
    public let doorOpen: SVMDoorStatus?
    public let trunkOpen: Bool?
    public let imageSize: [Int]?
    public let offset: Int?
    public let utcTime: String?
}

public struct SVMDoorStatus: Codable {
    public let frontLeft: Int?
    public let frontRight: Int?
    public let backLeft: Int?
    public let backRight: Int?
}

public struct SVMGPSDetail: Codable {
    public let coordLat: Double?
    public let coordLon: Double?
    public let coordType: Int?
    public let head: Int?
    public let speed: Int?
    public let speedUnit: Int?
    public let time: String?
}

public struct SVMResponse: Codable {
    public let responseHeader: ResponseHeader?
    public let result: SVMResult?
}

public struct ResponseHeader: Codable {
    public let responseCode: Int?
    public let responseDesc: String?
}

