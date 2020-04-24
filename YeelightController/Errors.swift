//
//  Errors.swift
//  YeelightController
//
//  Created by Keith Lee on 2020/04/24.
//  Copyright © 2020 Keith Lee. All rights reserved.
//

import Foundation



// make an error handler where every time an error is thrown, a didSet variable will notify any other part of a program



public enum DiscoveryError: Error {
    case tcpInitFailed(String)
    case propertyKey
    case idValue
}


public enum ListenerError: Error {
    case listenerFailed
    case noConnectionFound
}

public enum ConnectionError: Error {
    case endpointNotFound
    case connectionNotMade
    case receiveData(String)
}


public enum RequestError: Error {
    case stringToData
    case methodNotValid // not yet used
}


public enum JSONError: Error {
    case jsonObject
    case errorObject
    case response(String)
    case noData
    case unknown(Any?)
}


// change this or make a new one to reflect the new state updater?
public enum LightStateUpdateError: Error {
    case value(String)
}


public enum MethodError: Error {
    case valueBeyondMin(String)
    case valueBeyondMax(String)
    case fewerChangesThanStatesEntered
}


