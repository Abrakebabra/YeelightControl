//
//  LightCommand.swift
//  YeelightController
//
//  Created by Keith Lee on 2020/04/24.
//  Copyright © 2020 Keith Lee. All rights reserved.
//

import Foundation
import Network // for noLimitTCP listener


// =============================================================================
// SUMMARY =====================================================================
// =============================================================================

/*
 
 Primary:       LightCommand  (a supporting class to class Light)
 Supporting:    InputOptions
 
 LightCommand is a structure designed to eliminate errors in commands sent to the light.  It ensures that all methods and parameters meet the light's protocol.
 
 InputOptions railroads input options from String and Int into safe and understandable enumerations that handle the conversion into data types according to Yeelight's protocol.
 
 
 Standard command:
 do {
    let message: String = try LightCommand.CommandType(parameters).string()
    LightInstance.communicate(message)
 }
 catch {
 
 }
 
 flowStart command:
 do {
    let flowExpressions = LightCommand.flowStart.CreateExpressions()
    flowExpressions.addState(parameters for n state)
    flowExpressions.addState(parameters for n+1 state)
    let message: String = try LightCommand.flowStart(parameters, flowExpressions).string()
    LightInstance.communicate(message)
 }
 catch {
 
 }
 
 flowStop must be sent before the light will accept another command if it is in flow mode.
 
 */

// =============================================================================
// CONTENTS ====================================================================
// =============================================================================

// Significant items listed

// public enum InputOptions
// public enum InputOptions.Effect
// public enum InputOptions.OnOff
// public enum InputOptions.NumOfStateChanges
// public enum InputOptions.OnCompletion
// public enum InputOptions.SetState

// public struct LightCommand
// private struct LightCommand.methodParamString
// private struct LightCommand.valueInRange
// public struct LightCommand.colorTemp
// public struct LightCommand.colorRGB
// public struct LightCommand.colorHSV
// public struct LightCommand.brightness
// public struct LightCommand.power
// public struct LightCommand.flowStart
// public struct LightCommand.flowStart.CreateExpressions
// public struct LightCommand.flowStart.CreateExpressions.addState
// public struct LightCommand.flowStop
// public struct LightCommand.colorAndBrightness
// public struct LightCommand.colorAndBrightness.rgb
// public struct LightCommand.colorAndBrightness.hsv
// public struct LightCommand.colorAndBrightness.colorTemp
// public struct LightCommand.limitlessChannel
// public struct LightCommand.setHardwareName


/// Railroads input options from String and Int into safe and understandable enumerations that handle the conversion into data types according to Yeelight's protocol.
public enum InputOptions {
    
    /// Gradual or sudden change.
    public enum Effect {
        case sudden
        case smooth
        
        fileprivate func string() -> String {
            switch self {
            case .sudden:
                return "sudden"
            case .smooth:
                return "smooth"
            }
        }
    } // InputOptions.Effect
    
    /// Switch on or off.
    public enum OnOff {
        case on
        case off
        
        fileprivate func string() -> String {
            switch self {
            case .on:
                return "on"
            case .off:
                return "off"
            }
        }
    } // InputOptions.OnOff
    
    /// How many state changes for flowStart.
    public enum NumOfStateChanges {
        case infinite
        /// Number of state changes.  Must be equal or higher than number of states added.
        case finite(count: Int)
        
        fileprivate func int() -> Int {
            switch self {
            case .infinite:
                return 0
            case .finite(let count):
                return count
            }
        }
    } // InputOptions.NumOfStateChanges
    
    /// What the light should do when it exits a flow state.
    public enum OnCompletion {
        case returnPrevious
        case stayCurrent
        case turnOff
        
        fileprivate func int() -> Int {
            switch self {
                
            /// return to previous setting.
            case .returnPrevious:
                return 0
                
            /// finish flow and remain on that setting.
            case .stayCurrent:
                return 1
                
            case .turnOff:
                return 2
            }
        }
    } // InputOptions.OnCompletion
    
    /// Creates a tuple of 4 integers for each color state.  RGB and color temp modes only.  No hsv mode.
    public enum SetState {
        /// rgb range: 1-16777215, brightness range: 1-100, duration min = 50ms (as default).
        case rgb(rgb: Int, brightness: Int, duration: Int)
        /// color_temp range: 1700-6500, brightness range: 1-100, duration min = 50ms (as default)
        case colorTemp(colorTemp: Int, brightness: Int, duration: Int)
        /// duration min = 50ms (as default)
        case wait(duration: Int)
        
        // returns [duration, mode, rgb or color_temp val, bright_val]
        // min duration here is 50ms as opposed to 30 elsewhere
        fileprivate func params() throws -> [Int] {
            switch self {
            case .rgb(let rgb, let brightness, let duration):
                try LightCommand().valueInRange("rgb_value", rgb, min: 1, max: 16777215)
                try LightCommand().valueInRange("bright_val", brightness, min: 1, max: 100)
                try LightCommand().valueInRange("duration", duration, min: 50)
                return [duration, 1, rgb, brightness]
            
            case .colorTemp(let colorTemp, let brightness, let duration):
                try LightCommand().valueInRange("color_temp", colorTemp, min: 1700, max: 6500)
                try LightCommand().valueInRange("bright_val", brightness, min: 1, max: 100)
                try LightCommand().valueInRange("duration", duration, min: 50)
                return [duration, 2, colorTemp, brightness]
                
            case .wait(let duration):
                try LightCommand().valueInRange("duration", duration, min: 50)
                return [duration, 7, 0, 0]
            }
        }
    } // InputOptions.SetState
} // enum InputOptions




/// A structure to eliminate errors in commands sent to the light.  It ensures that all methods and parameters meet the light's protocol.
public struct LightCommand {
    //"effect" support two values: "sudden" and "smooth". If effect is "sudden", then the color temperature will be changed directly to target value, under this case, the third parameter "duration" is ignored. If effect is "smooth", then the color temperature will be changed to target value in a gradual fashion, under this case, the total time of gradual change is specified in third parameter "duration".
    //"duration" specifies the total time of the gradual changing. The unit is milliseconds. The minimum support duration is 30 milliseconds.
    
    // encode commands to required format for light
    private func methodParamString(_ method: String, _ param1: Any? = nil, _ param2: Any? = nil, _ param3: Any? = nil, _ param4: Any? = nil) -> String {
        /*
         JSON COMMANDS
         {"id":1,"method":"set_default","params":[]}
         {"id":1,"method":"set_scene", "params": ["hsv", 300, 70, 100]}
         {"id":1,"method":"get_prop","params":["power", "not_exist", "bright"]}
         */
        
        // different commands have different value types
        var parameters: [Any] = []
        
        // in order, append parameters to array.
        if let param1 = param1 {
            parameters.append(param1)
        }
        if let param2 = param2 {
            parameters.append(param2)
        }
        if let param3 = param3 {
            parameters.append(param3)
        }
        if let param4 = param4 {
            parameters.append(param4)
        }
        
        return """
        "method":"\(method)", "params":\(parameters)
        """
    } // LightCommand.methodParamString()
    
    
    // checks that a range is within the bounds per specifications
    fileprivate func valueInRange(_ valueName: String, _ value: Int, min: Int, max: Int? = nil) throws -> Void {
        
        guard value >= min else {
            throw MethodError.valueBeyondMin("\(valueName) of \(value) below minimum inclusive of \(min)")
        }
        
        if max != nil {
            guard value <= max! else {
                throw MethodError.valueBeyondMax("\(valueName) of \(value) above maximum inclusive of \(max!)")
            }
        }
    } // LightCommand.valueBoundCheck()
    
    
    // no get_prop method
    
    /// Set color temperature.  1700-6500 Kelvin.
    public struct colorTemp {
        private let method: String = "set_ct_abx"
        private let p1_ct_value: Int
        private let p2_effect: String
        private let p3_duration: Int
        
        /// temp range: 1700-6500, duration min = 30ms (as default)
        public init(temp: Int, effect: InputOptions.Effect, duration: Int = 30) throws {
            try LightCommand().valueInRange("color_temp", temp, min: 1700, max: 6500)
            try LightCommand().valueInRange("duration", duration, min: 30)
            self.p1_ct_value = temp
            self.p2_effect = effect.string()
            self.p3_duration = duration
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method, self.p1_ct_value, self.p2_effect, self.p3_duration)
        }
    } // LightCommand.set_colorTemp
    
    
    /// Set the RGB value of the light.
    public struct colorRGB {
        private let method = "set_rgb"
        private let p1_rgb_value: Int
        private let p2_effect: String
        private let p3_duration: Int
        
        /// rgb range: 1-16777215, duration min = 30ms (as default)
        public init(rgb: Int, effect: InputOptions.Effect, duration: Int = 30) throws {
            try LightCommand().valueInRange("rgb_value", rgb, min: 1, max: 16777215)
            try LightCommand().valueInRange("duration", duration, min: 30)
            self.p1_rgb_value = rgb
            self.p2_effect = effect.string()
            self.p3_duration = duration
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method, self.p1_rgb_value, self.p2_effect, self.p3_duration)
        }
    } // LightCommand.set_rgb
    
    
    /// Set the hue and saturation of the light.
    public struct colorHSV {
        private let method: String = "set_hsv"
        private let p1_hue_value: Int
        private let p2_sat_value: Int
        private let p3_effect: String
        private let p4_duration: Int
        
        /// hue range: 0-359, sat range: 0-100, duration min = 30ms (as default)
        public init(hue: Int, sat: Int, effect: InputOptions.Effect, duration: Int = 30) throws {
            try LightCommand().valueInRange("hue_value", hue, min: 0, max: 359)
            try LightCommand().valueInRange("sat_value", sat, min: 0, max: 100)
            try LightCommand().valueInRange("duration", duration, min: 30)
            self.p1_hue_value = hue
            self.p2_sat_value = sat
            self.p3_effect = effect.string()
            self.p4_duration = duration
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method, self.p1_hue_value, self.p2_sat_value, self.p3_effect, self.p4_duration)
        }
    } // LightCommand.set_hsv
    
    
    /// Set the brightness of the light.
    public struct brightness {
        private let method: String = "set_bright"
        private let p1_bright_value: Int
        private let p2_effect: String
        private let p3_duration: Int
        
        /// brightness range: 1-100, duration min = 30ms (as default)
        public init(brightness: Int, effect: InputOptions.Effect, duration: Int = 30) throws {
            try LightCommand().valueInRange("bright_value", brightness, min: 1, max: 100)
            try LightCommand().valueInRange("duration", duration, min: 30)
            self.p1_bright_value = brightness
            self.p2_effect = effect.string()
            self.p3_duration = duration
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method, self.p1_bright_value, self.p2_effect, self.p3_duration)
        }
    } // LightCommand.set_bright
    
    
    /// Turn the light on or off.
    public struct power {
        private let method: String = "set_power"
        private let p1_power: String
        private let p2_effect: String
        private let p3_duration: Int
        // has optional 4th parameter to switch to mode but excluding
        
        /// duration min = 30ms (as default)
        public init(turn onOff: InputOptions.OnOff, effect: InputOptions.Effect, duration: Int = 30) throws {
            try LightCommand().valueInRange("duration", duration, min: 30)
            self.p1_power = onOff.string()
            self.p2_effect = effect.string()
            self.p3_duration = duration
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method, self.p1_power, self.p2_effect, self.p3_duration)
        }
    } // LightCommand.set_power
    
    
    // no toggle method
    // no set_default method
    
    
    /// Program an order of states for the light to flow through.  Can be a finite number of state changes, or an infinite loop until stopped.
    public struct flowStart {
        
        /// create a saved array holding all added states.  addState() subsequently to append to array. This object is passed directly as a parameter to set_colorFlow.init()
        public struct CreateExpressions {
            private var allExpressions: [Int] = []
            
            /// append a new flow state to the CreateExpressions array.  rgb range: 1-16777215, color_temp range: 1700-6500, hue range: 0-359, sat range: 0-100, brightness range: 1-100, duration min = 30ms (as default)
            public mutating func addState(expression: InputOptions.SetState) throws {
                try self.allExpressions.append(contentsOf: expression.params())
                
            }
            
            // output this to a clean string "1, 2, 3, 4" with no square parenthesis
            fileprivate func output() -> (Int, String) {
                var tupleString: String = ""
                
                for i in self.allExpressions {
                    
                    if tupleString.count < 1 {
                        tupleString.append(contentsOf: String(i))
                    } else {
                        tupleString.append(contentsOf: ", \(String(i))")
                    }
                }
                
                // Each state has 4 values.  Returns number of states.
                // Enums.setState will only pass through 4 digits each time
                return (self.allExpressions.count / 4, tupleString)
            }
        }
        
        
        // {"id":1, "method":"start_cf", "params":[4, 2, "1000,2,2700,100"]}
        
        private let method: String = "start_cf"
        private let p1_count: Int
        private let p2_action: Int
        private let p3_flow_expression: String // custom type to ensure correct usage?
        
        /// CreateExpressions object required with subsequent addState().  Number of state changes must be equal or higher than number of state changes.
        public init(numOfStateChanges change_count: InputOptions.NumOfStateChanges, whenComplete onCompletion: InputOptions.OnCompletion, flowExpression: LightCommand.flowStart.CreateExpressions) throws {
            
            let expressions: (Int, String) = flowExpression.output()
            let expressionCount: Int = expressions.0
            self.p1_count = change_count.int()
            self.p2_action = onCompletion.int()
            self.p3_flow_expression = expressions.1
            
            guard self.p1_count >= expressionCount else {
                throw MethodError.fewerChangesThanStatesEntered
            }
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(method, p1_count, p2_action, p3_flow_expression)
        }
    } // LightCommand.set_colorFlow
    
    
    /// Cancels the current color flow state.
    public struct flowStop {
        private let method: String = "stop_cf"
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method)
        }
    } // LightCommand.set_colorFlowStop
    
    
    /// Send rgb, hsv, or color temp change, along with brightness in a single command.
    public struct colorAndBrightness {
        // leaving out color flow because it doesn't benefit from having an additional method through set_scene whereas rgb and ct can adjust brightness in a single command rather than separately.
        // Might review color flow in the future (10 April 2020).
        
        /// Red, green, blue.
        public struct rgb {
            private let method: String = "set_scene"
            private let p1_method: String = "color"
            private let p2_rgb: Int
            private let p3_bright: Int
            
            /// rgb range: 1-16777215, brightness range: 1-100
            public init(rgb: Int, brightness: Int) throws {
                try LightCommand().valueInRange("rgb_value", rgb, min: 1, max: 16777215)
                try LightCommand().valueInRange("bright_value", brightness, min: 1, max: 100)
                self.p2_rgb = rgb
                self.p3_bright = brightness
            }
            
            public func string() -> String {
                return LightCommand().methodParamString(self.method, self.p1_method, self.p2_rgb, self.p3_bright)
            }
        } // LightCommand.set_scene.rgb_bright
        
        /// Hue, saturation, brightness.
        public struct hsv {
            private let method: String = "set_scene"
            private let p1_method: String = "hsv"
            private let p2_hue: Int
            private let p3_sat: Int
            private let p4_bright: Int
            
            /// hue range: 0-359, saturation range: 0-100, brightness range: 1-100
            public init(hue: Int, sat: Int, brightness: Int) throws {
                try LightCommand().valueInRange("hue_value", hue, min: 0, max: 359)
                try LightCommand().valueInRange("sat_value", sat, min: 0, max: 100)
                try LightCommand().valueInRange("bright_value", brightness, min: 1, max: 100)
                self.p2_hue = hue
                self.p3_sat = sat
                self.p4_bright = brightness
            }
            
            /// output as string in correct format for the light
            public func string() -> String {
                return LightCommand().methodParamString(self.method, self.p1_method, self.p2_hue, self.p3_sat, self.p4_bright)
            }
        } // LightCommand.set_scene.hsv_bright
        
        /// Color temperature in Kelvin.  1700-6500K.
        public struct colorTemp {
            private let method: String = "set_scene"
            private let p1_method: String = "ct"
            private let p2_color_temp: Int
            private let p3_bright: Int
            
            /// color temp range: 1700-6500 Kelvin, brightness range: 1-100
            public init(temp: Int, brightness: Int) throws {
                try LightCommand().valueInRange("color_temp", temp, min: 1700, max: 6500)
                try LightCommand().valueInRange("bright_value", brightness, min: 1, max: 100)
                self.p2_color_temp = temp
                self.p3_bright = brightness
            }
            
            /// output as string in correct format for the light
            public func string() -> String {
                return LightCommand().methodParamString(self.method, self.p1_method, self.p2_color_temp, self.p3_bright)
            }
        } // LightCommand.set_scene.color_temp_bright
    } // LightCommand.set_scene
    
    
    // no cron_add method
    // no cron_get method
    // no cron_del method
    // no set_adjust method
    
    
    /// Special TCP connection with no limit to the number of commands.  The light does not send back any responses.  A state update is sent back when the limitless channel is closed.
    public class limitlessChannel {
        /*
         "action" the action of set_music command. The valid value can be:
         0: turn off music mode.
         1: turn on music mode.
         "host" the IP address of the limitless TCP server.
         "port" the TCP port application is listening on.
         
         Request:
         {"id":1,"method":"set_music","params":[1, “192.168.0.2", 54321]}
         {"id":1,"method":"set_music","params":[0]}
         
         Response:
         {"id":1, "result":["ok"]}
         
         When control device wants to start music mode:
         - it needs start a TCP server firstly
         - then call “set_music” command to let the device know the IP and Port of the TCP listen socket.
         - After received the command, LED device will try to connect the specified peer address.
         - control device should then send all supported commands through this channel without limit to simulate any music effect.
         - The control device can stop music mode by explicitly send a stop command or just by closing the socket.
         
         TO DO:
         Build method for sending params
         Build listener and handlers
         
         - Set up listener, start and just use listener.port after it starts
         - save that port - use an escaping closure
         - send message to light notifying local ip and listener port (add IP to existing function)
         - save that one new connection
         - create new tcp connection instance with that
         */
        
        
        /*
         FUNCTION'S CONTROL FLOW EXPLAINED
         (Weds April 22, 2020, 2:02am) because I didn't document it the first time, because I finished it the day before at 3:30am and went straight to bed.
         
         Each step is copied and pasted into the appropriate location within this class.
         
         Step 1:  Class instance in Thread A (calling thread) is created
         let message = try LightCommand.limitlessChannel(light: light, state: .on).string()
         
         Step 2:  self.p1_action and self.p2_listenerHost are initalised
         
         Step 3:  Listener function is called asynchonously and runs in its own Thread B.
         
         Step 4:  The listener function has an escaping closure (listener port escaping) that will be called when the listener's status is ready.
         
         Step 5:  init is now waiting at end of closure before completion, blocking the calling thread (Thread A).  LOCK 1. *(See appendix for timeout details)
         
         Step 6:  Listener is now waiting at end of closure before completion (LOCK 2), on a timeout of 1 second if target IP is not found, which will cancel the listener.
         
         Step 7:  Once listener state is ready, it passes the port it selected to the escaping closure which sets self.p3_listenerPort and RELEASE LOCK 1.
         
         Step 8:  Initialiser is now complete.  The string is sent to the light. (listener still waiting in Thread B).
         
         Step 9:  The light receives the message and now attempts to connect to the listener's IP and Port.
         
         Step 10:  Listener finds the light, checks its IP against the light it was targetting.  If the IP found does not match, it will ignore.  If the IP matches, it will create a new Connection instance and save it directly to the Light instance passed to this Struct.  If found, it will immediately RELEASE LOCK 2 in the listener.
         
         Step 11:  Listener is cancelled and function is now complete.
         
         * Appendix:  If the listener times out, the listener port is nil and the self.string() function filters the nil value out.  Method, p1 and p2 are passed to the Light.communicate() function which sends this to the light.  The command is missing port and the light rejects this as invalid and ignores it with no response.
         
         */
        private let method: String = "set_music"
        private let p1_action: Int
        private var p2_listenerHost: String?
        private var p3_listenerPort: Int?
        
        private var listener: NWListener?
        private let targetLight: Light
        private let controlQueue = DispatchQueue(label: "Control Queue")
        private let controlGroup = DispatchGroup()
        
        
        
        /// closure(listenerPort: Int)
        private func listen(_ closure:@escaping (Int) -> Void) throws -> Void {
            
            // ... step 3 continues asynchronously... to step 6 below
            
            // control flow for function
            let listenerGroup = DispatchGroup()
            // queue
            let serialQueue = DispatchQueue(label: "TCP Queue")
            // setup listener in class to be cancelled via another function
            self.listener = try? NWListener(using: .tcp)
            // was listener successfully set up?
            guard let listener = self.listener else {
                throw ListenerError.listenerFailed
            }
            
            
            listener.newConnectionHandler = { (newConn) in
                
                // STEP 9:  The light receives the message and now attempts to connect to the listener's IP and Port.
                
                if let remoteEnd = newConn.currentPath?.remoteEndpoint,
                    let targetIP = self.targetLight.tcp.remoteHost {
                    
                    switch remoteEnd {
                    case .hostPort(let host, let port):
                        
                        if host == targetIP {
                            
                            // STEP 10:  Listener finds the light, checks its IP against the light it was targetting.  If the IP found does not match, it will ignore.  If the IP matches, it will create a new Connection instance and save it directly to the Light instance passed to this Struct.  If found, it will immediately RELEASE LOCK 2 in the listener.
                            
                            self.targetLight.limitlessTCP = Connection(existingConn: newConn, existingQueue: serialQueue, remoteHost: host, remotePort: port, receiveLoop: false)
                            listenerGroup.leave()
                        } // if new connection IP and target IP match
                        
                    default:
                        return
                    } // switch statement
                } // remote end and target IP unwrapped
            } // listener
            
            
            listener.stateUpdateHandler = { (newState) in
                switch newState {
                case .ready:
                    
                    // STEP 7:  Once listener state is ready, it passes the port it selected to the escaping closure which sets self.p3_listenerPort and RELEASE LOCK 1.
                    
                    // get port and allow it to be accessed in closure to be used as parameter in command to light
                    if let listenerPort = listener.port?.rawValue {
                        closure(Int(listenerPort))
                    }
                case .failed(let error):
                    print("listener failed error: \(error)")
                default:
                    return
                }
            }
            
            
            listenerGroup.enter()
            listener.start(queue: serialQueue)
            
            // length of time to wait until
            let waitTime: UInt64 = 1 // default timeout seconds
            let futureTime = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + waitTime * 1000000000)
            
            // STEP 6:  Listener is now waiting at end of closure before completion (LOCK 2), on a timeout of 1 second if target IP is not found, which will cancel the listener, and TIMEOUT RELEASE LOCK 1. *(See appendix for details)
            
            // wait 1 second to establish limitless TCP.  If not found, cancel listener.
            if listenerGroup.wait(timeout: futureTime) == .timedOut {
                print("Listener: No connection available for music TCP")
                listener.cancel()
                listenerGroup.leave()
                throw ListenerError.noConnectionFound
            }
            
            // STEP 11:  Listener is cancelled and entire function is now complete.
            
            // on success
            listener.cancel()
        } // LightCommand.limitlessChannel.listen()
        
        
        /// light: target light to affect, and simple .on or .off.  Off instances will cancel the limitless TCP connection, and upon cancellation will deinit the Connection instance.
        public init(light: Light, switch state: InputOptions.OnOff) throws {
            
            //  STEP 1:  instance in Thread A (calling thread) is created
            
            self.targetLight = light // save reference to target light
            
            switch state {
            case .on:
                
                if let mode = self.targetLight.state.limitlessTCPMode {
                    if mode == true {
                        print("Already an existing limitless TCP connection")
                        throw ConnectionError.connectionNotMade
                    }
                }
                
                self.p1_action = 1
                
                // find the local IP
                guard let localEndpoint = self.targetLight.tcp.getHostPort(endpoint: .local) else {
                    throw ConnectionError.endpointNotFound
                }
                
                // local IP is listener IP to send to light
                self.p2_listenerHost = String(reflecting: localEndpoint.0)
                
                // STEP 2:  self.p1_action and self.p2_listenerHost are initalised
                
                self.controlGroup.enter()
                
                // STEP 3:  Listener function is called asynchonously and runs in its own Thread B.
                self.controlQueue.async {
                    do {
                        try self.listen() {
                            (port) in
                            // STEP 4:  The listener function has an escaping closure (listener port escaping) that will be called when the listener's status is ready.
                            self.p3_listenerPort = port
                            print("listener port found")
                            self.controlGroup.leave() // control unlock
                        }
                    }
                    catch let error {
                        print(error)
                    }
                } // controlQueue.async
                
            case .off:
                self.p1_action = 0
                // connection cancel and deinit is handled by Light class.
            } // switch
            
            // STEP 5:  init is now waiting at end of closure before completion, blocking the calling thread (Thread A).  LOCK 1. Next step in listen().
            
            // length of time to wait until
            let futureTime = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + 500000000) // 0.5s
            if self.controlGroup.wait(timeout: futureTime) == .timedOut {
                print("listener failed to set up and establish port")
            } // control lock
            
            // Step 8:  Initialiser is now complete.  The string is sent to the light. (listener still waiting in Thread B).  Next step in listener newConn handler.
            
        } // LightCommand.limitlessChannel.init()
        
        
        /// output as string in correct format for the light
        public func string() -> String {
            // the listener with a DispatchGroup lock should stop the init from returning before it finds the
            return LightCommand().methodParamString(self.method, self.p1_action, self.p2_listenerHost, self.p3_listenerPort)
        }
        
    } // LightCommand.limitlessChannel
    
    
    public struct setHardwareName {
        private let method: String = "set_name"
        private let p1_name: String
        
        public init(new newName: String) {
            self.p1_name = newName
        }
        
        /// output as string in correct format for the light
        public func string() -> String {
            return LightCommand().methodParamString(self.method, self.p1_name)
        }
    } // LightCommand.setHardwareName
    
    // no bg_set_xxx / bg_toggle method
    // no dev_toggle method
    // no adjust_bright method
    // no adjust_ct method
    // no adjust_color method
    // no bg_adjust_xx method
    
    
} // struct LightCommand
