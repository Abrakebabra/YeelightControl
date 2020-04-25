//
//  Connection.swift
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
 
 Connection has two initialisers.  One for creating a new Connection instance from a remote IP and port, and one for creating a new Connection instance from an already established connection.
 
 statusReady, statusCancelled and statusFailed are all called each time the status handler updates the status.  This is used to perform any actions when the connection is at that state.
 
 If any errors result from trying to receive a message, the auto-receive recursion will discontinue.
 
 */



/// Handles the connection
public class Connection {
    // local addr, port
    public var localHost: NWEndpoint.Host?
    public var localPort: NWEndpoint.Port? // not used, but here for completion
    
    // remote addr, port
    public var remoteHost: NWEndpoint.Host?
    public var remotePort: NWEndpoint.Port?
    
    // dispatch management
    internal let serialQueue: DispatchQueue
    internal let dispatchGroup = DispatchGroup()
    
    // Connection
    public var conn: NWConnection
    
    internal var sendCompletion = NWConnection.SendCompletion.contentProcessed { (error) in
        if error != nil {
            print("Send error: \(error as Any)")
            return
        }
    } // sendCompletion
    
    // if true, will initiate a recursive receiver
    private var receiveLoop: Bool = false
    
    public enum EndpointLocation {
        case local
        case remote
    }
    
    
    // Closures called upon status changes
    public var statusReady: (() throws -> Void)? // used to find ports
    public var statusCancelled: (() -> Void)? // used to deinit musicTCP
    public var statusFailed: (() -> Void)? // can be used to deinit a light
    
    public var status: String = "unknown" {
        didSet {
            if status == "ready" {
                do {
                    try statusReady?()
                }
                catch let error {
                    print("status ready closure error: \(error)")
                }
                
            } else if status == "cancelled" {
                statusCancelled?()
                
            } else if status == "failed" {
                statusFailed?()
            }
        } // didSet
    } // status
    
    
    // not expecting to receive multi-message data
    // each time newData is set, the closure will execute anywhere it is called, able to access the data
    /// Option to view data received from lights.  This closure is called every time data is received.
    public var newDataReceived: ((Data?) -> Void)?
    private var newData: Data? {
        didSet {
            newDataReceived?(newData)
        }
    }
    
    
    // Get the local port opened to send
    // Return nil if no hostPort connection found
    internal func getHostPort(endpoint: EndpointLocation) -> (NWEndpoint.Host, NWEndpoint.Port)? {
        
        let endpointLocation: NWEndpoint?
        
        switch endpoint {
        case .local:
            endpointLocation = self.conn.currentPath?.localEndpoint
        case .remote:
            endpointLocation = self.conn.currentPath?.remoteEndpoint
        }
        
        // safely unwrap
        if let unwrappedEndpoint = endpointLocation {
            switch unwrappedEndpoint {
            case .hostPort(let host, let port):
                return (host, port)
            default:
                return nil
            }
        } else {
            return nil
        }
    } // Connection.getHostPort()
    
    
    // handles the receiving from tcp conn with light
    private func receiveRecursively() -> Void {
        self.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { (data, _, _, error) in
            // Data?, NWConnection.ContentContext?, Bool, NWError?
            
            
            if error != nil {
                var host = "Unknown"
                if let unwrappedHost = self.remoteHost {
                    host = String(reflecting: unwrappedHost)
                }
                print("Conn receive error: \(host):  \(String(reflecting: error))")
                
            } else {
                self.newData = data
                self.receiveRecursively()
            }
        } // conn.receive closure
    } // Connection.receiveRecursively()
    
    
    // separated so that init overrides don't need to include all this again
    private func stateUpdateHandler() {
        
        var host = "Unknown IP"
        var port = "Unknown Port"
        
        if let unwrappedHost = self.remoteHost {
            host = String(reflecting: unwrappedHost)
        }
        
        if let unwrappedPort = self.remotePort {
            port = String(reflecting: unwrappedPort)
        }
        
        self.conn.stateUpdateHandler = { (newState) in
            switch(newState) {
            case .setup:
                self.status = "setup"
            case .preparing:
                self.status = "preparing"
            case .ready:
                self.status = "ready"
                print("\(host): \(port) ready")
            case .waiting(let error):
                self.status = "waiting"
                print("\(host): \(port) waiting with error: \(String(reflecting: error))")
            case .failed(let error):
                self.status = "failed"
                print("\(host): \(port), connection failed with error: \(String(reflecting: error))")
            case .cancelled:
                self.status = "cancelled"
                print("\(host): \(port) connection cancelled")
            @unknown default:
                // recommended in case of future changes
                self.status = "unknown"
                print("Unknown status for \(host): \(port)")
            } // switch
        } // stateUpdateHandler closure
    } // stateUpdateHandler()
    
    
    // init new connection
    internal init(host: NWEndpoint.Host, port: NWEndpoint.Port, serialQueueLabel: String, connType: NWParameters, receiveLoop: Bool) {
        
        self.remoteHost = host
        self.remotePort = port
        
        // label the queue
        self.serialQueue = DispatchQueue(label: serialQueueLabel)
        
        // create initial connection
        self.conn = NWConnection(host: host, port: port, using: connType)
        
        // start connection
        self.conn.start(queue: self.serialQueue)
        
        // start state update handler
        self.stateUpdateHandler()
        
        // once connection is ready, save local host and port
        self.statusReady = {
            // used for establishing music mode tcp connections so code to find local port is cleaner
            let localHostPort = self.getHostPort(endpoint: .local)
            if let localHostPort = localHostPort {
                self.localHost = localHostPort.0
                self.localPort = localHostPort.1
            } else {
                print("Can't establish local host and port")
            }
            
            // actively receive messages received and set up new receiver
            if receiveLoop == true {
                self.receiveRecursively()
            }
            
        } // statusReady closure
        
    } // Connection.init() newConn
    
    
    // init with existing connection
    internal init(existingConn: NWConnection, existingQueue: DispatchQueue, remoteHost: NWEndpoint.Host, remotePort: NWEndpoint.Port, receiveLoop: Bool) {
        
        // for identification purposes
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        
        // save reference to the existing queue
        self.serialQueue = existingQueue
        
        // save reference to the existing connection
        self.conn = existingConn
        
        // start connection
        self.conn.start(queue: self.serialQueue)
        
        // start state update handler
        self.stateUpdateHandler()
        
        // once connection is ready, save local host and port
        self.statusReady = {
            // not required but for completeness
            let localHostPort = self.getHostPort(endpoint: .local)
            if let localHostPort = localHostPort {
                self.localHost = localHostPort.0
                self.localPort = localHostPort.1
            } else {
                print("Can't establish local host and port")
            }
            
            // actively receive messages received and set up new receiver
            if receiveLoop == true {
                self.receiveRecursively()
            }
        } // self.statusReady
        
    } // Connection.init() existingConn
    
    
} // class Connection
