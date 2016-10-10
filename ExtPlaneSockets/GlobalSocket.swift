//
//  LocationDistributor.swift
//  joinr
//
//  Created by Christian Praiß on 1/11/16.
//  Copyright © 2016 petesso GmbH. All rights reserved.
//

import UIKit

public protocol GlobalSocketDelegate: class {
    func globalSocketDidConnect(_ socket: GlobalSocket, timestamp: Date)
    func globalSocketDidDisconnect(_ socket: GlobalSocket, timestamp: Date)
    func globalSocketDidReceiveData(_ socket: GlobalSocket, data: SocketManagerResponse, timestamp: Date)
}

public enum GlobalSocketError: Error {
    case notConnected
    case connectionError
}

public class GlobalSocket: NSObject, SocketManagerDelegate {
    
    public static let sharedInstance: GlobalSocket = GlobalSocket()
    
    fileprivate (set) var retryTimer: Timer?
    fileprivate (set) var canRetry = true
    fileprivate (set) var socketManager = SocketManager()
    fileprivate (set) var delegates: [GlobalSocketDelegate] = [GlobalSocketDelegate]()
    fileprivate (set) public var connected: Bool = false {
        didSet(prev) {
            if connected != prev {
                if connected {
                    for delegate in delegates {
                        delegate.globalSocketDidConnect(self, timestamp: Date())
                    }
                }else{
                    for delegate in delegates {
                        delegate.globalSocketDidDisconnect(self, timestamp: Date())
                    }
                }
            }
        }
    }
    
    override private init(){
        super.init()
        socketManager.delegate = self
    }
    
    fileprivate var cachedHost: URL!
    fileprivate var cachedPort: Int!
    
    // MARK: Connection

    func resetRetryLimit() {
        self.canRetry = true
        do {
            try self.attemptConnection(cachedHost, tcpPort: cachedPort)
        } catch {
            print(error)
        }
    }
    
    func attemptConnection(_ tcpHost: URL, tcpPort: Int) throws {
        cachedHost = tcpHost
        cachedPort = tcpPort
        if !canRetry || connected { return }
        print("attempting to connect")
        canRetry = false
        retryTimer?.invalidate()
        retryTimer = nil
        retryTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(GlobalSocket.resetRetryLimit), userInfo: nil, repeats: false)
        do {
            try self.socketManager.startSocket(tcpHost, port: tcpPort)
        }catch{
            throw GlobalSocketError.connectionError
        }
    }
    
    public func startSocket(_ url: URL, port: Int) throws {
        try attemptConnection(url, tcpPort: port)
    }
    
    public func stopSocket(){
        self.socketManager.stop()
    }
    
    // MARK: Own Delegates
    
    public func subscribeDelegate(_ delegate: GlobalSocketDelegate) {
        if self.delegates.contains(where: { (delegateFromArray) -> Bool in
            return delegate === delegateFromArray
        }) {
            print("already had delegated")
        } else {
            self.delegates.append(delegate)
        }
    }
    
    public func unsubscribeDelegate(_ delegate: GlobalSocketDelegate) {
        if let index = self.delegates.index(where: { (delegateFromArray) -> Bool in
            return delegate === delegateFromArray
        }) {
            self.delegates.remove(at: index)
        } else {
            print("GlobalSocket: delegate for unsubscribing was not found")
        }
    }
    
    // MARK: Socket Manager Delegate
    
    func socketManagerDidDisconnect(_ manager: SocketManager, error: Error?) {
        connected = false
        canRetry = false
        retryTimer?.invalidate()
        retryTimer = nil
        if let error = error {
            print(error)
            retryTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(GlobalSocket.resetRetryLimit), userInfo: nil, repeats: false)
        }else{
            // Stopped by hand
        }
    }
    
    func socketManagerDidReceiveData(_ manager: SocketManager, data: SocketManagerResponse) {
        for delegate in delegates {
            delegate.globalSocketDidReceiveData(self, data: data, timestamp: Date())
        }
    }
    
    func socketManagerDidConnect(_ manager: SocketManager, host: String, port: UInt16) {
        self.connected = true
        self.retryTimer?.invalidate()
        self.retryTimer = nil
        self.canRetry = true
        print("connected to \(host):\(port)")
    }

    // MARK: Send Data
    
    public func send(string: String) throws {
        if connected {
            try self.socketManager.send(string: string)
        }else{
            throw GlobalSocketError.notConnected
        }
    }
}
