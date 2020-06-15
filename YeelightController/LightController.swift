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


// MARK: |<  enum DiscoveryWait
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



// MARK: |<  class UDPConnection
fileprivate class UDPConnection {
    
    // connection
    let dispatchGroup = DispatchGroup()
    let serialQueue = DispatchQueue(label: "serialQueue")
    let udpParams = NWParameters.udp
    var listener: NWListener?
    let targetHostPort = NWEndpoint.hostPort(host: "239.255.255.250", port: 1982)
    var connection: NWConnection?
    
    // search message
    let searchMsg: Data = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1982\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb".data(using: .utf8)!
    
    let sendCompletion = NWConnection.SendCompletion.contentProcessed {
        (error) in
        if let error = error {
            print("UDP Connection send error: \(error)")
        }
        
        print("search message sent")
    }
    
    
    /*
     Rebuild for OSX 10.15.5 and Xcode 11.5
      - setup listener
      - get listener port
      - listener stateUpdateHandler
      - start listener
      - handle new connection
      - save port to outside variable
      - state ready
      - udp connection
      - send message
      - close connection upon message sent
     */
    
    
    // MARK: getWiFiAddress
    func getWiFiAddress() -> String? {
        // source: https://stackoverflow.com/questions/30748480/swift-get-devices-wifi-ip-address
        var address : String?
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            //if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {  // **ipv6 committed
            if addrFamily == UInt8(AF_INET){

                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {

                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        return address
    }
    
    
    // MARK: func connectAndSend
    fileprivate func connectAndSend() {
        
        self.connection?.stateUpdateHandler = {
            (state) in
            switch state {
            case .setup:
                print("udp connection setup")
            case .preparing:
                print("udp connection preparing")
            case .ready:
                print("udp connection ready")
                print("local endpoint: \(String(describing: self.connection?.currentPath?.localEndpoint))")
                self.connection?.send(content: self.searchMsg, completion: self.sendCompletion)
            case .cancelled:
                print("udp connection cancelled")
            case .waiting(let error):
                print("udp connection waiting with error: \(error)")
            case .failed(let error):
                print("udp connection failed with error: \(error)")
            @unknown default:
                print("udp connection unknown error")
            }
        }
        
        self.connection?.start(queue: self.serialQueue)
        
    }
    
    
    
    // MARK: func search
    // Listen for reply from multicast
    fileprivate func search(wait mode: DiscoveryWait, _ closure: @escaping ([Data]) -> Void) throws {
        
        print("search function entered")
        
        let listenerGroup = DispatchGroup()
        var waitCount: Int = 0 // default lightCount
        var waitTime: UInt64 = 5 // default timeout seconds
        let futureTime = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + waitTime * 1_000_000_000)
        
        
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
        
        
        
        
        self.listener = try? NWListener(using: .udp)
        
        
        // Holds all the data received
        var dataArray: [Data] = []
        
        
        self.listener?.stateUpdateHandler = {
            (state) in
            switch state {
            case .setup:
                print("listener setting up")
            case .waiting(let error):
                print("udp listener waiting with error: \(error)")
            case .ready:
                print("udp listener ready")
                
                let localHostString = self.getWiFiAddress()
                let listenerPort = self.listener?.port
                
                if let localHostString = localHostString, let listenerPort = listenerPort {
                    
                    let localHost = NWEndpoint.Host(localHostString)
                    self.udpParams.requiredLocalEndpoint =
                        .hostPort(host: localHost, port: listenerPort)
                    self.udpParams.acceptLocalOnly = true
                    self.udpParams.allowLocalEndpointReuse = true
                    
                    self.connection = NWConnection(to: self.targetHostPort, using: self.udpParams)
                    
                    self.connectAndSend()
                    
                }
                
                
                
            case .cancelled:
                print("udp listener cancelled")
            case .failed(let error):
                print("udp listener failed with error: \(error)")
                
            @unknown default:
                print("unknown error")
            }
        }
        
        
        listener?.newConnectionHandler = {
            (udpNewConn) in
            // create connection, listen to reply and save data
            udpNewConn.start(queue: self.serialQueue)
            
            udpNewConn.receiveMessage {
                (data, _, _, error) in
                
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
            } // receiveMessage
        } // newConnectionHandler
        
        // start the search
        self.listener?.start(queue: self.serialQueue)
        
        // wait for light count, or timeout if not all expected lights found or set to search for a set amount of time
        if listenerGroup.wait(timeout: futureTime) == .success {
            print("listener successfully found \(dataArray.count) lights.")
            
        } else {
            print("listener cancelled after \(futureTime.uptimeNanoseconds / 1_000_000_000) seconds.  Found \(dataArray.count) lights.")
            listenerGroup.leave()
        }
        
        // pass data to the closure, cancel the listener and signal that the calling function can progress with the data
        closure(dataArray)
        self.listener?.cancel()
    } // UDPConnection.listener()
    
    
    
    
    
} // class UDPConnection



// =============================================================================
// CLASS LIGHTCONTROLLER =======================================================
// =============================================================================



// MARK: |<  class LightController
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
    
    
    // MARK: func ParseProperties
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
    
    
    // MARK: func createLight
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
    
    
    // MARK: func decodeParseAndEstablish
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
    
    
    // MARK: func findLight
    // finder
    private func findLight(alias: Alias, id: ID) -> Light? {
        for (lightID, light) in self.lights {
            if id == lightID {
                return light
            }
        }
        return nil
    }
    
    
    // MARK: func setAliasReference
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
    
    
    // MARK: init
    public init() {
        return
    }
    
    
    
    // =========================================================================
    // LIGHTCONTROLLER FUNCTIONS ===============================================
    // =========================================================================
    
    
    // MARK: func discover
    /// Discover and save lights found.  Default option is timeout of 2 seconds.
    public func discover(wait mode: DiscoveryWait = .timeoutSeconds(2)) {
        // clear all existing lights and save the space in case of re-discovery
        for (_, value) in self.lights {
            value.tcp.conn.cancel()
        }
        
        self.lights.removeAll(keepingCapacity: true)
        
        var udp: UDPConnection? = UDPConnection()
        
        // establish
        do {
            try udp?.search(wait: mode) {
                (dataArray) in
                
                for i in dataArray {
                    self.decodeParseAndEstablish(i)
                }
            }
        }
        catch let error {
            print(error)
        }
        
        udp = nil
        
    } // LightController.discover()
    
    
    // MARK: func setLightAlias
    /// Set an alias for the lights instead of using the IDs.  Closure must return a string back into the function as the alias.  Handling of input method is done here.  NameTaken Bool returns true if the name already exists. Code locked until unique alias provided. An empty string will save the light's ID as the alias.
    public func setLightAlias(closureInputMethod:@escaping (NameTakenBool) -> String) -> Void {
        
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
                    let input = closureInputMethod(nameTaken)
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
            } // aliasQueue.async
            
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

