//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by Alex Chan on 2017/2/15.
//  Copyright © 2017年 sunset. All rights reserved.
//

import NetworkExtension

import SwiftyBeaver
import NEKit
import Resolver
import Localize_Swift
//import Dotzu
import CocoaLumberjack
import CocoaLumberjackSwift

let log = SwiftyBeaver.self

class PacketTunnelProvider: NEPacketTunnelProvider {

    var server: GCDHTTPProxyServer!
    var interface: TUNInterface!

    override init() {
        super.init()

        let console = ConsoleDestination()  // log to Xcode Console
        console.useNSLog = true
        let file = FileDestination()  // log to default swiftybeaver.log file
//        let cloud = SBPlatformDestination(appID: "dGP8WW", appSecret: "c0Yboblgojpz7lvrmZvpnvzMhvsbovkv", encryptionKey: "e2J6bldyrne2ieOxtvhpbouebFu4sPr4") // to cloud
        
        log.addDestination(console)
        log.addDestination(file)
//        log.addDestination(cloud)
//
//        #if DEBUG
//            Dotzu.sharedManager.enable()
//        #endif
        
        DDLog.removeAllLoggers()
        DDLog.add(DDASLLogger.sharedInstance, with: .debug)        
        DDLog.add(DDTTYLogger.sharedInstance, with: .debug)

        //        DDLog.add(DDTTYLogger.sharedInstance(), with: .info)

    }

    deinit {

        log.removeAllDestinations()
    }



    func getNetworkSetings() -> NEPacketTunnelNetworkSettings {
        // the `tunnelRemoteAddress` is meaningless because we are not creating a tunnel.
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "8.8.8.8")
        networkSettings.mtu = 1500

        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.100"], subnetMasks: ["255.255.255.255"])

            ipv4Settings.includedRoutes = [NEIPv4Route.default()]

//            ipv4Settings.excludedRoutes = [
//                NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
//                NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
////                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
//                NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
//                NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
////                NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
//            ]

        networkSettings.iPv4Settings = ipv4Settings

        let proxySettings = NEProxySettings()
        //        proxySettings.autoProxyConfigurationEnabled = true
        //        proxySettings.proxyAutoConfigurationJavaScript = "function FindProxyForURL(url, host) {return \"SOCKS 127.0.0.1:\(proxyPort)\";}"
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: 9090)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: 9090)
        proxySettings.excludeSimpleHostnames = true
        proxySettings.exceptionList = ["*.apple.com", "apple.com","*.baidu.com","*.google.com.*","*.google.com"]
        // This will match all domains
        proxySettings.matchDomains = [""]
        networkSettings.proxySettings = proxySettings

        // the 198.18.0.0/15 is reserved for benchmark.

            let DNSSettings = NEDNSSettings(servers: ["223.5.5.5"])
            DNSSettings.matchDomains = [""]
            DNSSettings.matchDomainsNoSearch = true
            networkSettings.dnsSettings = DNSSettings

        return networkSettings

    }

    override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {

        let setting = UserDefaults(suiteName: kAppGroupName)!
        guard  setting.string(forKey: kAdapterType) == "ss" else {
            // currently only ss supported
            completionHandler(SmartVPNError.invalidConfig as Error)
            return
        }

        let port = setting.integer(forKey: kAdapterPort)
        guard let key = setting.string(forKey: kAdapterKey) ,
              let method = setting.string(forKey: kAdapterMethod) ,
            let host = setting.string(forKey: kAdapterServer)  else {

            completionHandler(SmartVPNError.invalidConfig as Error)
            return
        }

        let ssAdapterFactory = ShadowsocksAdapterFactory(serverHost: host, serverPort: port, protocolObfuscaterFactory: ShadowsocksAdapter.ProtocolObfuscater.OriginProtocolObfuscater.Factory(), cryptorFactory:
            ShadowsocksAdapter.CryptoStreamProcessor.Factory(password: key, algorithm: CryptoAlgorithm(rawValue: method.uppercased())!), streamObfuscaterFactory:ShadowsocksAdapter.StreamObfuscater.OriginStreamObfuscater.Factory())

        let directAdapterFactory = DirectAdapterFactory()
//        let httpAdapterFactory = HTTPAdapterFactory(serverHost: kProxyServer, serverPort: kProxyPort, auth: nil)

//        let chinaRule =  CountryRule(countryCode: "CN", match: true, adapterFactory: directAdapterFactory)
//        let appleDomains = DomainListRule(adapterFactory: directAdapterFactory, criteria: [DomainListRule.MatchCriterion.suffix(".icloud-content.com"), DomainListRule.MatchCriterion.suffix(".apple.com"), DomainListRule.MatchCriterion.suffix(".icloud.com")])
//
        let allRule = AllRule(adapterFactory: directAdapterFactory)
//
//        let manager = RuleManager(fromRules: [appleDomains, chinaRule, allRule], appendDirect: true)
        
        let testRules = DomainListRule(adapterFactory: ssAdapterFactory, criteria: [
                DomainListRule.MatchCriterion.suffix("bing.com"),
                DomainListRule.MatchCriterion.suffix("baidu.com"),
//                DomainListRule.MatchCriterion.suffix("google.com"),
                DomainListRule.MatchCriterion.suffix("wikipedia.org")
            ])
        
        let manager = RuleManager(fromRules: [allRule])

        RuleManager.currentManager = manager

//        ObserverFactory.currentFactory = DebugObserverFactory()

        server = GCDHTTPProxyServer(address: IPAddress(fromString: "127.0.0.1"), port: Port(port: 9090))

//        Logger.info("GCDHTTPProxyServer server.start")
        try! server.start()

        RawSocketFactory.TunnelProvider = self

//        Logger.info("setTunnelNetworkSettings")

        
        setTunnelNetworkSettings(getNetworkSetings(), completionHandler: {
            [unowned self]  error in

            guard error == nil else {
//                log.error("Encountered an error setting up the network: \(error!)")
                completionHandler(error as! Error)
                return
            }

            self.interface = TUNInterface(packetFlow: self.packetFlow)

            let fakeIPPool = try! IPPool(range: IPRange(startIP: IPAddress(fromString: "172.169.1.0")!, endIP: IPAddress(fromString: "172.169.255.0")!))

            let dnsServer = DNSServer(address: IPAddress(fromString: "223.5.5.5")!, port: Port(port: 53), fakeIPPool: fakeIPPool)
            let resolver = UDPDNSResolver(address: IPAddress(fromString: "114.114.114.114")!, port: Port(port: 53))
            let resolver2 = AutoVPNDNSResolver()
            dnsServer.registerResolver(resolver2)
//            dnsServer.registerResolver(resolver)

            DNSServer.currentServer = dnsServer

            let tcpStack = TCPStack.stack
            tcpStack.proxyServer = self.server

            self.interface.register(stack: dnsServer)
            self.interface.register(stack: UDPDirectStack())
            self.interface.register(stack: tcpStack)
            
//            Logger.info("interface started")
            self.interface.start()
//            Logger.info("completionHandler")
                      completionHandler(nil)
        })

    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {

        interface.stop()
        interface = nil
        DNSServer.currentServer = nil

        server.stop()
        server = nil

        RawSocketFactory.TunnelProvider = nil

        completionHandler()

        // For unknown reason, the extension will be running for several extra seconds, which prevents us from starting another configuration immediately. So we crash the extension now.
        // I do not find any consequences.
        exit(EXIT_SUCCESS)

    }

}
