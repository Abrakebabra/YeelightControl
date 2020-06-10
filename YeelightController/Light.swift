//
//  Light.swift
//  YeelightController
//
//  Created by Keith Lee on 2020/04/24.
//  Copyright © 2020 Keith Lee. All rights reserved.
//

import Foundation
import Network


// =============================================================================
// SUMMARY =====================================================================
// =============================================================================

/*
 
 Primary:       Light
 Supporting:    State
 Supporting:    Info
 
 Light is an object that holds all the information about the light, connections, the current state, and the functions to parse and automatically handle data received from the light.  The light also handles any automated actions such as auto-cancelling and deinitialising the limitlessTCP connection object.
 
 Light.communicate() is its only user-called function and automatically detects which TCP connection it should use.
 
 
 State is not user set and is only updated from the light.  Data returned from the light with unsafe data types (such as a String with "on" and "off" for power, or 1 and 0 for mode on/off) are converted into safe data types (Bool).
 
 Info holds identifying and useful information about the light that is not actively updated.
 
 */


// ==========================================================================
// CONTENTS =================================================================
// ==========================================================================

// public struct State

// public struct Info

// public class Light
// private class Light.updateState
// private class Light.jsonDecodeAndHandle
// public class Light.communicate
// public class Light.printCommunications


// ==========================================================================
// SUPPORTING STRUCTS AND CLASSES ===========================================
// ==========================================================================



// MARK: |<  struct State
/// The current state of the light's properties
public struct State {
    public var power: Bool
    public var colorMode: Int  //  Modes:  1 RGB, 2 Color Temp, 3 HSV
    public var brightness: Int  // Percentage:  1-100  (0 not valid)
    public var colorTemp: Int  // colorMode 2:  1700-6500 (Yeelight 2)
    public var rgb: Int  // colorMode 1:  1-16777215 (hex: 0xFFFFFF)
    public var hue: Int  // colorMode 3: 0-359
    public var sat: Int  // colorMode 3:  0-100
    
    public var flowing: Bool?  // flowing or not
    public var flowParams: [Int]?  // tuple (4 integers) per state
    fileprivate var limitlessTCPModeOffNotify: (() -> Void)? // allows light to perform action if limitlessTCPMode is set to false
    public var limitlessTCPMode: Bool = false {
        didSet {
            if limitlessTCPMode == false {
                limitlessTCPModeOffNotify?()
            }
        }
    } // limitlessTCPMode on or off
    public var delayCountDownMins: Int?  // minutes until power off
    
    fileprivate init(_ power: String,
         _ colorMode: String, _ brightness: String,
         _ colorTemp: String, _ rgb: String, _ hue: String, _ sat: String) {
        
        if power == "on" {
            self.power = true
        } else {
            self.power = false
        }
        
        // default values just in case a light that has been factory-reset has nil for properties that have not yet been used
        
        if let colorModeInt = Int(colorMode) {
            self.colorMode = colorModeInt
        } else {
            self.colorMode = 1
        }
        if let brightInt = Int(brightness) {
            self.brightness = brightInt
        } else {
            self.brightness = 1
        }
        if let colorTempInt = Int(colorTemp) {
            self.colorTemp = colorTempInt
        } else {
            self.colorTemp = 1700
        }
        if let rgbInt = Int(rgb) {
            self.rgb = rgbInt
        } else {
            self.rgb = 0
        }
        if let hueInt = Int(hue) {
            self.hue = hueInt
        } else {
            self.hue = 0
        }
        if let satInt = Int(sat) {
            self.sat = satInt
        } else {
            self.sat = 0
        }
    } // init()
} // struct State



/// Identifying and useful information about light
public struct Info {
    public let id: String
    public var name: String
    public let model: String // Might be useful for lights with limited abilities
    public let support: String // Might be useful for lights with limited abilities
    
    fileprivate init(_ id: String, _ name: String, _ model: String, _ support: String) {
        self.id = id
        self.name = name
        self.model = model
        self.support = support
    }
} // struct Info



// ==========================================================================
// CLASS LIGHT ==============================================================
// ==========================================================================



// MARK: |<  class Light
public class Light {
    
    /// The current state of the light's properties.
    public var state: State
    public var tcp: Connection
    public var limitlessTCP: Connection?
    /// Identifying and useful information about light.
    public var info: Info
    /// Number of messages sent to this light.
    public let requestTicketLightID: Int
    public var requestTicket: Int = 0
    // Print communication received from light.  False by default.
    private var printCommunication: Bool = false
    private let deinitControl = DispatchGroup()
    
    
    // MARK: func updateState
    // update the state of the light
    private func updateState(_ key: String, _ value: Any) throws {
        switch key {
        case "power":
            guard let power = value as? String else {
                throw LightStateUpdateError.valueToDataTypeFailed("power to String failed")
            }
            
            self.state.power = power == "on" ? true : false
            
        case "bright":
            guard let brightness = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("brightness to Int failed")
            }
            self.state.brightness = brightness
            
        case "color_mode":
            guard let colorMode = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("colorTemp to Int failed")
            }
            self.state.colorMode = colorMode
            
        case "ct":
            guard let colorTemp = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("colorTemp to Int failed")
            }
            self.state.colorTemp = colorTemp
            
        case "rgb":
            guard let rgb = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("rgb to Int failed")
            }
            self.state.rgb = rgb
            
        case "hue":
            guard let hue = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("hue to Int failed")
            }
            self.state.hue = hue
            
        case "sat":
            guard let sat = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("sat to Int failed")
            }
            self.state.sat = sat
            
        case "name":
            guard let name = value as? String else {
                throw LightStateUpdateError.valueToDataTypeFailed("name to String failed")
            }
            self.info.name = name
            
        case "flowing":
            guard let flow = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("flow state to Bool failed")
            }
            self.state.flowing = flow == 1 ? true : false
            
        case "flow_params":
            guard let string: String = value as? String else {
                throw LightStateUpdateError.valueToDataTypeFailed("flow params to String failed")
            }
            
            let stringNoSpace: String = string.replacingOccurrences(of: " ", with: "")
            let stringComponents: [String] = stringNoSpace.components(separatedBy: ",")
            var params: [Int] = []
            
            for i in stringComponents {
                guard let intComponent = Int(i) else {
                    throw LightStateUpdateError.valueToDataTypeFailed("flow param component to Int failed")
                }
                params.append(intComponent)
            }
            
            self.state.flowParams = params
            
        case "music_on":
            guard let limitlessTCPMode = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("limitless TCP mode state to Bool failed")
            }
            self.state.limitlessTCPMode = limitlessTCPMode == 1 ? true : false
            
        case "delayoff":
            guard let mins = value as? Int else {
                throw LightStateUpdateError.valueToDataTypeFailed("delay countdown to Int failed")
            }
            self.state.delayCountDownMins = mins
            
        default:
            // don't throw error yet - might have more states that will update than anticipated
            print("Property key (\(key)) not handled.  Value is \(value)")
        } // switch
    } // Light.updateState()
    
    
    // MARK: func jsonDecodeAndHandle
    // decode response received from light and handle them
    private func jsonDecodeAndHandle(_ data: Data) throws {
        /*
         JSON RESPONSES
         
         Standard Responses
         {"id":1, "result":["ok"]}
         get_pro Response
         {"id":1, "result":["on", "", "100"]}
         
         State Update Response
         Sent to all tcp connections when state changed:
         {"method":"props","params":{"ct":6500}}
         
         Error Response
         {"id":2, "error":{"code":-1, “message”:"unsupported method"}}
         [String:[String:Any]]
         
         UNUSED:
         cron_get Response      [[String:Int]]
         {"id":1, "result":[{"type": 0, "delay": 15, "mix": 0}]}
         Won't use this response.
         cron methods can only turn off light after X minutes.  No need for a timer function.
         
         */
        
        /*
         Deserialize to json object
         Top level "result" key?  If yes, print results.
         Top level "error" key?  If yes, print error.
         Top level "params" key?  If yes, update light state with new data.
         
         */
        
        
        // jsonserialization object
        
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        
        
        // unpack the top level json object
        guard let topLevel = json as? [String:Any] else {
            throw JSONError.jsonObject("jsonDecodeAndHandle: Not a valid JSON object")
        }
        
        // results
        if let resultList = topLevel["result"] as? [String] {
            
            if self.printCommunication == true {
                if let id = topLevel["id"] as? Int {
                    // if there is a resultList
                    print("id \(id): \(resultList)")
                } else {
                    print("No id: \(resultList)")
                }
            }
            
            // errors
        } else if let error = topLevel["error"] as? [String:Any] {
            guard
                let errorCode: Int = error["code"] as? Int,
                let errorMessage: String = error["message"] as? String
                else {
                    // if can't unpack error object
                    throw JSONError.errorObject("jsonDecodeAndHandle: Not valid JSON object")
            } // guard let
            
            if let id = topLevel["id"] as? Int {
                throw JSONError.response("id: \(id)  Error Code \(errorCode): \(errorMessage)")
            } else {
                throw JSONError.response("Error Code \(errorCode): \(errorMessage)")
            }
            
            // change in state
        } else if let changedState = topLevel["params"] as? [String:Any] {
            for (key, value) in changedState {
                // switch function for updating state
                try self.updateState(key, value)
                
                if self.printCommunication == true {
                    print("\(self.info.id) updating '\(key)' to '\(value)'")
                }
                
            }
            
        } else {
            throw JSONError.unknown(json as Any)
        }
        
    } // Light.jsonDecode()
    
    
    
    // MARK: init
    internal init(_ id: String, _ ip: String, _ port: String,
         _ power: String, _ colorMode: String, _ brightness: String,
         _ colorTemp: String, _ rgb: String, _ hue: String, _ sat: String,
         _ name: String, _ model: String, _ support: String) throws {
        
        // Holds the light's current state
        self.state = State(power, colorMode, brightness, colorTemp, rgb, hue, sat)
        
        guard let portEndpoint = NWEndpoint.Port(port) else {
            throw DiscoveryError.tcpInitFailed("Port not found")
        }
        
        let tcpParams = NWParameters.tcp
        tcpParams.acceptLocalOnly = true
        
        // Holds the connection
        self.tcp = Connection(host: NWEndpoint.Host(ip), port: portEndpoint, serialQueueLabel: "TCP Queue", connType: tcpParams, receiveLoop: true)
        
        // Holds supporting information and identifier
        self.info = Info(id, name, model, support)
        
        // able to diagnose whether requests from a single or multiple lights throw an error.
        self.requestTicketLightID = Int.random(in: 1000..<9999)
        
        // handle new data received in closure from didSet var
        self.tcp.newDataReceived = { (data) in
            if let data = data {
                
                do {
                    try self.jsonDecodeAndHandle(data)
                }
                catch let error {
                    print("JSON decode error: \(error)\nData Received: \(String(describing: String(bytes: data, encoding: .utf8)))")
                }
                
                if self.printCommunication == true {
                    print("Received:  \(String(bytes: data, encoding: .utf8) ?? "Data unable to be decoded.")")
                }
            }
        }
        
        // if the light sends a signal that limitless TCP mode has been turned off.
        // if light is turned off during limitless TCP mode, limitless TCP mode is turned off, the light instance is notified, cancels the local connection and deinits connection.
        self.state.limitlessTCPModeOffNotify = {
            self.limitlessTCP?.conn.cancel()
            self.limitlessTCP?.statusCancelled = {
                self.limitlessTCP = nil
            }
            self.limitlessTCP = nil
            // print("limitless TCP mode connection cancelled") // do I want this?
        }
        
        self.limitlessTCP?.statusFailed = {
            self.limitlessTCP?.conn.cancel()
            self.limitlessTCP?.statusCancelled = {
                self.limitlessTCP = nil
            }
            self.limitlessTCP = nil
            // print("failed limitless TCP mode connection cancelled") // do I want this?
        }
        
    } // Light.init()
    
    
    
    // MARK: func communicate
    /// Send a command String to the light created by a LightCommand.___.string() command.
    public func communicate(_ methodParams: String) {
        // takes in a command
        // randomly generate an ID for that message
        // append string command to ID
        // convert to data
        // sends message to light
        // append ID to a dictionary with the message
        // awaits for a reply
        // sort through various replies or errors from light
        // return that reply to what called the function
        // throw errors found in JSON reply from light
        
        self.requestTicket += 1
        
        let requestJoined: String = "\(String(self.requestTicketLightID))\(String(self.requestTicket))"
        let requestInt: Int = Int(requestJoined)!
        
        let id: String = """
        "id":\(requestInt)
        """
        
        let message: String = """
        {\(id), \(methodParams)}\r\n
        """
        
        let requestContent = message.data(using: .utf8)
        
        var tcpConnection = self.tcp.conn
        
        // if limitless TCP mode has been established, all TCP commands are sent to the new connection without limit
        if self.state.limitlessTCPMode == true {
            // debug
            // print("self.state.limitlessTCPMode == true")
            if let limitlessTCPConn = self.limitlessTCP?.conn {
                tcpConnection = limitlessTCPConn
            }
        }
        
        // is this necessary?  TEST THIS
        if message == """
            {"id":1,"method":"set_music","params":[0]}
            """ {
                tcpConnection = self.tcp.conn
        }
        

        tcpConnection.send(content: requestContent, completion: self.tcp.sendCompletion)
        
        
        if self.printCommunication == true {
            
            if self.state.limitlessTCPMode == true {
                print("limitless TCP connection used")
            }
            
            if let unwrappedEndpoint = tcpConnection.currentPath?.remoteEndpoint {
                switch unwrappedEndpoint {
                case .hostPort(let host, let port):
                    print("Sent to host: \(host) and port: \(port)\n\(message)")
                default:
                    return
                }
            }
        }
    } // Light.communicate()
    
    
    // MARK: printCommunications
    /// Print communication received from light.  False by default.
    public func printCommunications(_ setting: Bool) {
        self.printCommunication = setting
    }
    
    
    
} // class Light



