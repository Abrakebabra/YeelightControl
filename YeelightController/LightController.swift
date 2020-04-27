//
//  LightController.swift
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
 
 Primary:       LightController
 Supporting:    UDPConnection
 
 LightController's purpose is to discover lights and store them.  The class can also rename them, pair the alias names with the light's IDs, and save them to an alias:Light pair.  If any connections fail and must be restarted, the lights can be re-discovered and the alias can be paired to the same light without the process needing to be re-performed.
 
 The class has been designed to detect and save the lights as fast as possible, and also give the user flexibility to search for the lights based on knowing how many to look for, or finding them based on a timeout.
 
 The lights are stored in a publicly accessible dictionary.  They are a reference type and can be copied to be used elsewhere.
 
 UDPConnection's purpose is to send a search advertisement to the lights, record all of the data sent back to a listener and to create a light object with the connection and state information from the light.
 */



// =============================================================================
// CONTENTS ====================================================================
// =============================================================================

// public enum DiscoveryWait

// fileprivate class UDPConnection
// fileprivate class UDPConnection.listener
// fileprivate class UDPConnection.sendSearchMessage
// fileprivate class UDPConnection.

// public class LightController
// private class LightController.parseProperties
// private class LightController.createLight
// private class LightController.decodeParseAndEstablish
// private class LightController.findLight
// private class LightController.setAliasReference
// public class LightController.discover
// public class LightController.setLightAlias


public enum DiscoveryWait {
    /// Look for this number of lights.  Time out if can't find.
    case lightCount(Int)
    /// Wait this many seconds and save whatever lights have been found within that time.
    case timeoutSeconds(Int)
    
    private func integer() -> Int {
        switch self {
        case .lightCount(let count):
            return count
        case .timeoutSeconds(let seconds):
            return seconds
        }
    }
}



// =============================================================================
// CLASS UDPCONNECTION =========================================================
// =============================================================================



fileprivate class UDPConnection: Connection {
    
    // search message
    private static let searchMsg: String = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1982\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb"
    private static let searchBytes = searchMsg.data(using: .utf8)
    
    
    
    fileprivate init() {
        let udpParams = NWParameters.udp
        udpParams.acceptLocalOnly = true
        
        super.init(host: "239.255.255.250", port: 1982,
                   serialQueueLabel: "UDP Queue", connType: udpParams,
                   receiveLoop: false)
    } // UDPConnection.init()
    
    
    // Listen for reply from multicast
    fileprivate func listener(on port: NWEndpoint.Port, wait mode: DiscoveryWait, _ closure: @escaping ([Data]) -> Void) {
        
        let listenerGroup = DispatchGroup()
        var waitCount: Int = 0 // default lightCount
        var waitTime: UInt64 = 5 // default timeout seconds
        let futureTime = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + waitTime * 1000000000)
        
        switch mode {
        // if mode is count, wait for light count before returning
        case .lightCount(let count):
            waitCount = count
            for _ in 0..<count {
                listenerGroup.enter()
            }
        // if mode is timeout, wait input-seconds before returning
        case .timeoutSeconds(let seconds):
            waitTime = UInt64(seconds)
            listenerGroup.enter()
        }
        
        
        guard let listener = try? NWListener(using: .udp, on: port) else {
            print("Listener failed")
            return
        }
        
        // Holds all the data received
        var dataArray: [Data] = []
        
        listener.newConnectionHandler = { (udpNewConn) in
            // create connection, listen to reply and save data
            udpNewConn.start(queue: self.serialQueue)
            
            udpNewConn.receiveMessage(completion: { (data, _, _, error) in
                
                if error != nil {
                    print(error.debugDescription)
                    
                }
                
                if let data = data {
                    switch mode {
                    case .lightCount:
                        if dataArray.count < waitCount {
                            dataArray.append(data) // save data
                            listenerGroup.leave() // reduce wait count
                        }
                        
                    case .timeoutSeconds:
                        dataArray.append(data)
                    } // switch
                } // data? unwrap
            }) // receiveMessage
            
        } // newConnectionHandler
        
        
        // start the light
        listener.start(queue: self.serialQueue)
        
        // wait time, or timeout if not all expected lights found
        if listenerGroup.wait(timeout: futureTime) == .success {
            print("listener successfully returned \(waitCount) lights")
            
        } else {
            print("listener cancelled after \(futureTime.uptimeNanoseconds / 1000000000) seconds")
        }
        
        // pass data to the closure, cancel the listener and signal that the calling function can progress with the data
        closure(dataArray)
        listener.cancel()
        self.dispatchGroup.leave() // unlock 2 (entered in self.sendSearchMessage)
    } // UDPConnection.listener()
    
    
    
    fileprivate func sendSearchMessage(wait mode: DiscoveryWait, _ closure:@escaping ([Data]) -> Void) {
        
        // 1 second to ready the connection
        let connPrepTimeout = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + 1 * 1000000000)
        
        self.dispatchGroup.enter() // lock 1
        // wait for self.conn to be in ready state
        
        self.statusReady = {
            self.dispatchGroup.leave()
        }
        
        // wait lock 1
        // waiting for connection state to be .ready
        if self.dispatchGroup.wait(timeout: connPrepTimeout) == .timedOut {
            print("Search UDP connection timed out")
            return
        } // wait lock 1 (with timeout)
        
        // send a search message
        self.conn.send(content: UDPConnection.searchBytes, completion: self.sendCompletion)
        
        // safely unwrap local port
        guard let localHostPort = self.getHostPort(endpoint: .local) else {
            print("Couldn't find local port")
            return
        }
        
        self.dispatchGroup.enter() // lock 2
        // Listen for light replies and create a new light tcp connection
        self.listener(on: localHostPort.1, wait: mode) {
            (dataArray) in
            closure(dataArray)
        }
        
        // wait for UDPConnection.listener() to collect data
        self.dispatchGroup.wait() // wait lock 2 - unlock in listener() - also with timeout
        self.conn.cancel()
    } // UDPConnection.sendSearchMessage()
    
    
} // class UDPConnection



// =============================================================================
// CLASS LIGHTCONTROLLER =======================================================
// =============================================================================



public class LightController {
    // aliases easier to read
    private typealias Property = String
    private typealias Value = String
    
    public typealias Alias = String
    public typealias ID = String
    public typealias NameTakenBool = Bool
    
    /// Stores all discovered lights as [idSerial : Light]
    public var lights: [String : Light] = [:]
    /// Stores all bindings of alias names to light IDs as [Alias : ID]
    public var savedAliasIDs: [Alias : ID] = [:]
    /// Stores all discovered lights as [Alias : Light]
    public var alias: [Alias : Light] = [:]
    
    
    // parse string data to store light data
    private func parseProperties(Decoded decoded: String) -> [Property:Value] {
        // dictionary of all properties cleaned and separated
        var propertyDict: [Property:Value] = [:]
        
        // separate message string into separate lines
        var propertyList: [String] =
            decoded.components(separatedBy: "\r\n")
        
        // remove HTTP header
        // remove empty element at end that the final "\r\n" creates
        propertyList.removeFirst()
        propertyList.removeLast()
        
        // marker that indicates ip and port in array
        let addressMarker: String = "Location: yeelight://"
        
        // if find address marker, remove marker and separate ip and port
        // into own individual key value pairs.
        // Otherwise, create key value pair for each property
        for i in propertyList {
            if i.contains(addressMarker) {
                let ipPortString: String = i.replacingOccurrences(of: addressMarker, with: "")
                let ipPort: [String] = ipPortString.components(separatedBy: ":")
                propertyDict["ip"] = ipPort[0]
                propertyDict["port"] = ipPort[1]
                
            } else {
                let keyValue: [String] =
                    i.components(separatedBy: ": ")
                
                // in case a future update changes the response which results in an index range error
                if keyValue.count == 2 {
                    let key: Property = keyValue[0]
                    let value: Value = keyValue[1]
                    
                    // add key value pair to dictionary
                    propertyDict[key] = value
                }
                
            }
        }
        // possible to return empty
        return propertyDict
    } // LightController.parseData()
    
    
    // convert strings to data types and create struct
    private func createLight(_ property: [Property:Value]) throws -> Light {
        
        guard
            let ip = property["ip"],
            let port = property["port"],
            let id = property["id"],
            let power = property["power"],
            let brightness = property["bright"],
            let colorMode = property["color_mode"],
            let colorTemp = property["ct"],
            let rgb = property["rgb"],
            let hue = property["hue"],
            let sat = property["sat"],
            let name = property["name"],
            let model = property["model"],
            let support = property["support"]
            else {
                throw DiscoveryError.propertyKey
        }
        
        // create class Light instance
        let light = try Light(id, ip, port, power, colorMode, brightness, colorTemp, rgb, hue, sat, name, model, support)
        
        return light
    } // LightController.createLight()
    
    
    // handles replies received from lights with listener
    private func decodeParseAndEstablish(_ data: Data) {
        
        // decode data to String
        guard let decoded = String(data: data, encoding: .utf8) else {
            print("UDP data message received cannot be decoded")
            return
        }
        
        // separate properties into dictionary to inspect
        let properties: [Property:Value] = self.parseProperties(Decoded: decoded)
        
        // create tcp connection to each light and save that connection and data
        // print errors identified
        // save the light to class dictionary
        do {
            guard let id = properties["id"] else {
                throw DiscoveryError.idValue
            }
            
            if self.lights[id] == nil {
                
                // Add new light to dictionary if doesn't already exist
                self.lights[id] = try self.createLight(properties)
            }
            
        }
        catch let error {
            print(error)
        }
        
    } // LightController.decodeHandler()
    
    
    // finder
    private func findLight(alias: Alias, id: ID) -> Light? {
        for (lightID, light) in self.lights {
            if id == lightID {
                return light
            }
        }
        return nil
    }
    
    
    // sets discovered light instance to the saved aliases.  Could be existing and rediscovering lights in case of a connection error, or setting up new.
    private func setAliasReference() {
        // clear everything
        self.alias.removeAll(keepingCapacity: true)
        
        for (alias, aliasID) in self.savedAliasIDs {
            let light = self.findLight(alias: alias, id: aliasID)
            if let light = light {
                // pair light instance to alias key.
                self.alias[alias] = light
            }
        }
    }
    
    
    public init() {
        return
    }
    
    
    
    // =========================================================================
    // LIGHTCONTROLLER FUNCTIONS ===============================================
    // =========================================================================
    
    
    /// Discover and save lights found.  Default option is timeout of 2 seconds.
    public func discover(wait mode: DiscoveryWait = .timeoutSeconds(2)) {
        // clear all existing lights and save the space in case of re-discovery
        for (_, value) in self.lights {
            value.tcp.conn.cancel()
        }
        
        self.lights.removeAll(keepingCapacity: true)
        
        var udp: UDPConnection? = UDPConnection()
        
        // establish
        udp?.sendSearchMessage(wait: mode) { (dataArray) in
            for i in dataArray {
                self.decodeParseAndEstablish(i)
            }
        }
        
        udp = nil
        
    } // LightController.discover()
    
    
    /// Set an alias for the lights instead of using the IDs.  Closure must return a string back into the function as the alias.  Handling of input method is done here.  NameTaken Bool returns true if the name already exists. Code locked until unique alias provided. An empty string will save the light's ID as the alias.
    public func setLightAlias(inputMethod:@escaping (NameTakenBool) -> String) -> Void {
        
        let aliasGroup = DispatchGroup()
        let aliasQueue = DispatchQueue(label: "Alias Queue")
        
        var dimMessage = ""
        var showMessage = ""
        var defaultOn = ""
        
        // set message for dimming light
        do {
            dimMessage = try LightCommand.power(turn: .off, effect: .smooth).string()
            showMessage = try LightCommand.colorAndBrightness.colorTemp(temp: 5000, brightness: 100).string()
            defaultOn = try LightCommand.colorAndBrightness.hsv(hue: 60, sat: 100, brightness: 100).string()
        } catch let error {
            print(error)
        }
        
        
        
        
        // dim all the lights
        for (_, light) in self.lights {
            light.communicate(dimMessage)
        }
        
        
        for (id, light) in self.lights {
            var nameTaken = false
            var alias = id
            light.communicate(showMessage)
            aliasGroup.enter()
            // needs an input check to make sure the name doesn't already exist and if it does, to loop again.
            aliasQueue.async {
                
                while true {
                    let input = inputMethod(nameTaken)
                    if input != "" {
                        alias = input
                    }
                    if self.savedAliasIDs[alias] == nil {
                        break
                    } else {
                        nameTaken = true
                    }
                }
                
                aliasGroup.leave()
            }
            
            aliasGroup.wait()
            self.savedAliasIDs[alias] = id
            
            light.communicate(dimMessage)
        } // cycle through saved lights and save IDs to aliases
        
        
        // last step
        self.setAliasReference()
        
        /*
         How does alias work?
         - Makes a new dictionary and creates a reference to light dictionary (or the light dictionary ids?) - perhaps I'll need a separate dictionary storing all of the saved references from alias to id string, then the usable alias of alias to instance which is a direct reference which can be re-referenced upon a new discovery.
         
         send message to all lights to change to not obvious state
         
         go through dictionary of lights and light the first one.
         wait.
         prompt user for new name.
         confirm y/n.
         once confirmed, save that name and reference to the saved alias to ID dictionary
         release wait.
         
         go to next light and repeat until complete
         
         When all lights are complete, run through saved alias list, and any IDs that match the light instance IDs are then saved to alias:Light reference so that it can directly be accessed by name.
         */
        
        
        // turn on all the lights
        for (_, light) in self.lights {
            light.communicate(defaultOn)
        }
        
        
    }
    
    
} // class LightController

