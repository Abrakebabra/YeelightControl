//
//  Errors.swift
//  YeelightController
//
//  Created by Keith Lee on 2020/04/24.
//  Copyright © 2020 Keith Lee. All rights reserved.
//

import Foundation


/// LightController discovery errors
internal enum DiscoveryError: Error {
    case tcpInitFailed(String)
    case lightSearchTimedOut
    case propertyKey                // dictionary no element error when creating light
    case idValue                    // dictionary no element error when creating light
}


/// Connection errors
internal enum ConnectionError: Error {
    case localEndpointNotFound(String)
    case noConnectionFound(String)
    case connectionNotMade(String)
}


/// Light JSON decode errors
internal enum JSONError: Error {
    case jsonObject(String)
    case errorObject(String)
    case response(String)
    case unknown(Any?)
}


/// Light state update error
internal enum LightStateUpdateError: Error {
    case valueToDataTypeFailed(String)
}


/// LightCommand errors
internal enum MethodError: Error {
    case valueBeyondMin(String)
    case valueBeyondMax(String)
    case fewerChangesThanStatesEntered
}


