//
//  NETCPLink.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 5/23/19.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of TunnelKit.
//
//  TunnelKit is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  TunnelKit is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with TunnelKit.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import NetworkExtension
import TunnelKitCore
import TunnelKitAppExtension
import TunnelKitOpenVPNCore
import CTunnelKitOpenVPNProtocol

class NETCPLink: LinkInterface {
    private let impl: NWTCPConnection
    
    private let maxPacketSize: Int

    private let xorMethod: OpenVPN.XORMethod?

    private let xorMask: Data?

    init(impl: NWTCPConnection, maxPacketSize: Int? = nil, xorMethod: OpenVPN.XORMethod?) {
        self.impl = impl
        self.maxPacketSize = maxPacketSize ?? (512 * 1024)
        self.xorMethod = xorMethod
        xorMask = xorMethod?.mask
    }
    
    // MARK: LinkInterface
    
    let isReliable: Bool = true
    
    var remoteAddress: String? {
        (impl.remoteAddress as? NWHostEndpoint)?.hostname
    }
    
    var remoteProtocol: String? {
        guard let remote = impl.remoteAddress as? NWHostEndpoint else {
            return nil
        }
        return "TCP:\(remote.port)"
    }

    var packetBufferSize: Int {
        return maxPacketSize
    }
    
    func setReadHandler(queue: DispatchQueue, _ handler: @escaping ([Data]?, Error?) -> Void) {
        loopReadPackets(queue, Data(), handler)
    }
    
    private func loopReadPackets(_ queue: DispatchQueue, _ buffer: Data, _ handler: @escaping ([Data]?, Error?) -> Void) {
        
        // WARNING: runs in Network.framework queue
        impl.readMinimumLength(2, maximumLength: packetBufferSize) { [weak self] (data, error) in
            guard let self = self else {
                return
            }
            queue.sync {
                guard (error == nil), let data = data else {
                    handler(nil, error)
                    return
                }
                
                var newBuffer = buffer
                newBuffer.append(contentsOf: data)
                var until = 0
                let packets = PacketStream.packets(
                    fromInboundStream: newBuffer,
                    until: &until,
                    xorMethod: self.xorMethod?.native ?? .none,
                    xorMask: self.xorMask
                )
                newBuffer = newBuffer.subdata(in: until..<newBuffer.count)
                self.loopReadPackets(queue, newBuffer, handler)
                
                handler(packets, nil)
            }
        }
    }
    
    func writePacket(_ packet: Data, completionHandler: ((Error?) -> Void)?) {
        let stream = PacketStream.outboundStream(
            fromPacket: packet,
            xorMethod: xorMethod?.native ?? .none,
            xorMask: xorMask
        )
        impl.write(stream) { (error) in
            completionHandler?(error)
        }
    }
    
    func writePackets(_ packets: [Data], completionHandler: ((Error?) -> Void)?) {
        let stream = PacketStream.outboundStream(
            fromPackets: packets,
            xorMethod: xorMethod?.native ?? .none,
            xorMask: xorMask
        )
        impl.write(stream) { (error) in
            completionHandler?(error)
        }
    }
}

extension NETCPSocket: LinkProducer {
    public func link(userObject: Any?) -> LinkInterface {
        let xorMethod = userObject as? OpenVPN.XORMethod
        return NETCPLink(impl: impl, maxPacketSize: nil, xorMethod: xorMethod)
    }
}
