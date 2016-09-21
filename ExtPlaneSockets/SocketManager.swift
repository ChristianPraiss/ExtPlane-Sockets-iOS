//
//  SocketManager.swift
//  joinr
//
//  Created by Christian Praiß on 1/7/16.
//  Copyright © 2016 petesso GmbH. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

protocol SocketManagerDelegate {
    func socketManagerDidReceiveData(_ manager: SocketManager, data: SocketManagerResponse)
    func socketManagerDidDisconnect(_ manager: SocketManager, error: Error?)
    func socketManagerDidConnect(_ manager: SocketManager, host: String, port: UInt16)
}

public struct SocketManagerResponse {
    let content: String
    let rawContent: Data
    
    var description: String {
        return "\(rawContent.count) / \(content)"
    }
}

/**
 
 
 TODO: REWRITE
 
 
 
 The SocketManager communicates with the remote server via the LDT (Live data transfer) Protocol. This protocol defines rules to process live data like location updates.
 The Socket is always ready to receive new data.
 
 LDT protocol:
 
 **-Requests:**
 
 - Format: "**{Route}** / **{Data}**\r\n"
 - Explanation:  The **Route** parameter is is used distinguish the request's **Route** on the server.
 **Data** is an UTF8 encoded String which may contain JSON data.
 The packet is terminated by the "\r\n" sequence.
 
 **-Reponses:**
 
 - Format: "**{Status}** / **{Data}**\r\n"
 - Explanation:  The **Status** parameter is modeled after the standard HTTP parameters.
 The only parameter that's different is 100, which means new data.
 It is emitted to show that the sent data is not a response to a request but new data.
 **Data** is an UTF8 encoded String which may contain JSON data.
 The packet is terminated by the "\r\n" sequence.
 */
class SocketManager: NSObject, GCDAsyncSocketDelegate {
    
    enum SocketManagerError: Error {
        case serializationError
        case connectionError
    }
    
    /// This sequence is used to detect the end of a request and may never be used for anything except that
    fileprivate static let responseEndData = "\r\n".data(using: String.Encoding.utf8)!
    var delegate: SocketManagerDelegate?
    fileprivate var shouldDisconnect = false
    fileprivate(set) var connected: Bool = false
    
    /// Attempts to connect to a socket
    func startSocket(_ url: URL, port: Int? = nil) throws {
        do {
            if let host = url.host, let port = (url as NSURL).port?.intValue ?? port {
                try socket.connect(toHost: host, onPort: UInt16(port))
            } else {
                throw SocketManagerError.connectionError
            }
        }catch{
            throw error
        }
    }
    
    fileprivate lazy var socket: GCDAsyncSocket = {
        let socket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
        socket.autoDisconnectOnClosedReadStream = true
        return socket
    }()
    
    func send(string: String) throws {
        if let data = (string + "\r\n").data(using: String.Encoding.utf8) {
            self.socket.write(data, withTimeout: -1, tag: 0)
        }else{
            throw SocketManagerError.serializationError
        }
    }
    
    func stop(){
        shouldDisconnect = true
        socket.disconnect()
    }
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String,port: UInt16) {
        connected = true
        sock.startTLS([String: NSNumber]());
        delegate?.socketManagerDidConnect(self, host: host, port: port)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        if let string = String(data: data, encoding: String.Encoding.utf8) {
            var parts = string.components(separatedBy: "  ")
            if let statusString = parts.first, let status = Int(statusString) , status != 0 && statusString.characters.count != 0 {
                var content = ""
                if parts.count == 2 {
                    content = parts[1]
                }else if parts.count > 2 {
                    // Reassemble separated parts to allow using '/' in content
                    for i in 1...parts.count {
                        if parts[i].contains("\r\n") {
                            print("\(#function) - L\(#line): socket data error, termination character occurred more than once")
                            return
                        }
                        content += (parts[i] + " / ")
                    }
                    parts[1] = content
                }
                // Remove termination characters from content body or return empty body
                if content.characters.count > 2 {
                    content = content.substring(to: content.characters.index(content.endIndex, offsetBy: -1))
                }else{
                    content = ""
                }
                delegate?.socketManagerDidReceiveData(self, data: SocketManagerResponse(content: content, rawContent: content.data(using: String.Encoding.utf8) ?? Data()))
            }else{
                print("\(#function) - L\(#line): socket data error")
            }
        }else{
            print("\(#function) - L\(#line): socket data error")
        }
        
        // Prepare for next data arriving
        sock.readData(to: SocketManager.responseEndData, withTimeout: -1, tag: 0)
    }
    
    public func socketDidCloseReadStream(_ sock: GCDAsyncSocket) {
        connected = false
        delegate?.socketManagerDidDisconnect(self, error: nil)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        // Prepare fore reading response
        sock.readData(to: SocketManager.responseEndData, withTimeout: -1, tag: 0)
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        connected = false
        if !shouldDisconnect {
            delegate?.socketManagerDidDisconnect(self, error: err)
        }
    }
}
