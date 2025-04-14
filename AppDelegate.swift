import Flutter
import UIKit
import CallKit
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    // MARK: - Properties
    private var callObserver: CXCallObserver?
    private var callStartTime: Date?
    private var flutterChannel: FlutterMethodChannel?
    private var isCallActive = false
    private var currentCallDuration: Int = 0
    private var callTimer: Timer?
    private var lastKnownDuration: Int = 0
    private var isOutgoingCall = false
    
    // MARK: - Application Lifecycle
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Ensure window and root view controller are properly set up
        guard let controller = window?.rootViewController as? FlutterViewController else {
            print("Failed to get FlutterViewController")
            return false
        }
        
        // Setup Flutter plugins
        do {
            try GeneratedPluginRegistrant.register(with: self)
        } catch {
            print("Failed to register Flutter plugins: \(error)")
            return false
        }
        
        // Setup method channel
        setupMethodChannel(controller: controller)
        
        // Setup call observer
        setupCallObserver()
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Private Methods
    private func setupMethodChannel(controller: FlutterViewController) {
        flutterChannel = FlutterMethodChannel(
            name: "callkit_channel",
            binaryMessenger: controller.binaryMessenger
        )
        
        flutterChannel?.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkCallStatus":
            result([
                "isActive": isCallActive,
                "duration": currentCallDuration,
                "isOutgoing": isOutgoingCall
            ])
            
        case "getCurrentDuration":
            result(currentCallDuration)
            
        case "requestPermissions":
            requestPermissions(result: result)
            
        case "initiateOutgoingCall":
            isOutgoingCall = true
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func setupCallObserver() {
        #if DEBUG
            callObserver = CXCallObserver()
            callObserver?.setDelegate(self, queue: .main)
        #else
            // Check if the app is running in a release environment
            if Bundle.main.bundleIdentifier == "com.agent.mygenie" {
                callObserver = CXCallObserver()
                callObserver?.setDelegate(self, queue: .main)
            } else {
                print("Call Kit functionality is not enabled for this environment")
            }
        #endif
        // callObserver = CXCallObserver()
        // callObserver?.setDelegate(self, queue: .main)
    }
    
    private func startCallTimer() {
        guard isOutgoingCall else { return }
        
        print("Starting call timer for outgoing call")
        callTimer?.invalidate()
        currentCallDuration = 0
        callStartTime = Date()
        lastKnownDuration = 0
        
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCallDuration()
        }
    }
    
    private func updateCallDuration() {
        guard let startTime = callStartTime else { return }
        
        currentCallDuration = Int(Date().timeIntervalSince(startTime))
        lastKnownDuration = currentCallDuration
        
        print("Current duration: \(currentCallDuration)")
        
        flutterChannel?.invokeMethod("onCallDurationUpdate", arguments: [
            "duration": currentCallDuration,
            "isOutgoing": true
        ])
    }
    
    private func stopCallTimer() {
        guard isOutgoingCall else { return }
        
        print("Stopping call timer")
        callTimer?.invalidate()
        callTimer = nil
        
        if let startTime = callStartTime {
            let finalDuration = Int(Date().timeIntervalSince(startTime))
            currentCallDuration = max(finalDuration, lastKnownDuration)
            print("Final duration calculated: \(currentCallDuration)")
        } else {
            currentCallDuration = lastKnownDuration
            print("Using last known duration: \(lastKnownDuration)")
        }
    }
    
    private func requestPermissions(result: @escaping FlutterResult) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                print("Microphone permission granted: \(granted)")
                result(granted)
            }
        }
    }
    
    private func resetCallState() {
        isCallActive = false
        isOutgoingCall = false
        currentCallDuration = 0
        lastKnownDuration = 0
        callStartTime = nil
        callTimer?.invalidate()
        callTimer = nil
    }
}

// MARK: - CXCallObserverDelegate
extension AppDelegate: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        // Update outgoing call status if needed
        if !isOutgoingCall {
            isOutgoingCall = call.isOutgoing
        }
        
        // Only process outgoing calls
        guard isOutgoingCall else {
            print("Ignoring incoming call")
            return
        }
        
        handleCallStateChange(call)
    }
    
    private func handleCallStateChange(_ call: CXCall) {
        if call.hasConnected && isOutgoingCall {
            handleCallConnected()
        }
        
        if call.hasEnded && isOutgoingCall {
            handleCallEnded()
        }
    }
    
    private func handleCallConnected() {
        print("Outgoing call connected")
        isCallActive = true
        startCallTimer()
        
        flutterChannel?.invokeMethod("onCallStarted", arguments: [
            "isOutgoing": true
        ])
    }
    
    private func handleCallEnded() {
        print("Outgoing call ended")
        isCallActive = false
        stopCallTimer()
        
        let finalDuration = max(currentCallDuration, lastKnownDuration)
        print("Sending final duration: \(finalDuration)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendCallEndedEvent(duration: finalDuration)
        }
    }
    
    private func sendCallEndedEvent(duration: Int) {
        flutterChannel?.invokeMethod("onCallEnded", arguments: [
            "duration": duration,
            "isOutgoing": true
        ])
        resetCallState()
    }
}

// MARK: - CXCall Extension
extension CXCall {
    var isOutgoing: Bool {
        return hasConnected && !hasEnded
    }
}

//import Flutter
//import UIKit
//import CallKit
//import AVFoundation
//
//@UIApplicationMain
//@objc class AppDelegate: FlutterAppDelegate {
//    private var callObserver: CXCallObserver?
//    private var callStartTime: Date?
//    private var flutterChannel: FlutterMethodChannel?
//    private var isCallActive = false
//    private var currentCallDuration: Int = 0
//    private var callTimer: Timer?
//    private var lastKnownDuration: Int = 0
//    private var isOutgoingCall = false  // Add this flag
//
//    override func application(
//        _ application: UIApplication,
//        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//    ) -> Bool {
//        GeneratedPluginRegistrant.register(with: self)
//
//        let controller = window?.rootViewController as! FlutterViewController
//        flutterChannel = FlutterMethodChannel(name: "callkit_channel",
//                                            binaryMessenger: controller.binaryMessenger)
//
//        setupCallObserver()
//
//        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
//    }
//
//    private func startCallTimer() {
//        guard isOutgoingCall else { return }  // Only start timer for outgoing calls
//        
//        print("Starting call timer for outgoing call")
//        callTimer?.invalidate()
//        currentCallDuration = 0
//        callStartTime = Date()
//        lastKnownDuration = 0
//        
//        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
//            guard let self = self else { return }
//            if let startTime = self.callStartTime {
//                self.currentCallDuration = Int(Date().timeIntervalSince(startTime))
//                self.lastKnownDuration = self.currentCallDuration
//                print("Current duration: \(self.currentCallDuration)")
//                self.flutterChannel?.invokeMethod("onCallDurationUpdate", arguments: [
//                    "duration": self.currentCallDuration,
//                    "isOutgoing": true
//                ])
//            }
//        }
//    }
//
//    private func stopCallTimer() {
//        guard isOutgoingCall else { return }  // Only process for outgoing calls
//        
//        print("Stopping call timer")
//        callTimer?.invalidate()
//        callTimer = nil
//        
//        if let startTime = callStartTime {
//            let finalDuration = Int(Date().timeIntervalSince(startTime))
//            currentCallDuration = max(finalDuration, lastKnownDuration)
//            print("Final duration calculated: \(currentCallDuration)")
//        } else {
//            currentCallDuration = lastKnownDuration
//            print("Using last known duration: \(lastKnownDuration)")
//        }
//    }
//
//    private func setupCallObserver() {
//        callObserver = CXCallObserver()
//        callObserver?.setDelegate(self, queue: DispatchQueue.main)
//        
//        flutterChannel?.setMethodCallHandler { [weak self] (call, result) in
//            guard let self = self else { return }
//            
//            switch call.method {
//            case "checkCallStatus":
//                result([
//                    "isActive": self.isCallActive,
//                    "duration": self.currentCallDuration,
//                    "isOutgoing": self.isOutgoingCall
//                ])
//            case "getCurrentDuration":
//                result(self.currentCallDuration)
//            case "requestPermissions":
//                self.requestPermissions(result: result)
//            case "initiateOutgoingCall":
//                self.isOutgoingCall = true  // Set flag when call is initiated from app
//                result(true)
//            default:
//                result(FlutterMethodNotImplemented)
//            }
//        }
//    }
//
//    private func requestPermissions(result: @escaping FlutterResult) {
//        AVAudioSession.sharedInstance().requestRecordPermission { granted in
//            print("Microphone permission granted: \(granted)")
//            result(granted)
//        }
//    }
//
//    private func resetCallState() {
//        isCallActive = false
//        isOutgoingCall = false
//        currentCallDuration = 0
//        lastKnownDuration = 0
//        callStartTime = nil
//        callTimer?.invalidate()
//        callTimer = nil
//    }
//}
//
//extension AppDelegate: CXCallObserverDelegate {
//    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
//        // Detect if it's an outgoing call
//        if !isOutgoingCall {
//            isOutgoingCall = call.isOutgoing
//        }
//        
//        // Only process outgoing calls
//        guard isOutgoingCall else {
//            print("Ignoring incoming call")
//            return
//        }
//
//        if call.hasConnected && isOutgoingCall {
//            print("Outgoing call connected")
//            isCallActive = true
//            startCallTimer()
//            
//            flutterChannel?.invokeMethod("onCallStarted", arguments: [
//                "isOutgoing": true
//            ])
//        }
//        
//        if call.hasEnded && isOutgoingCall {
//            print("Outgoing call ended")
//            isCallActive = false
//            stopCallTimer()
//            
//            let finalDuration = max(currentCallDuration, lastKnownDuration)
//            print("Sending final duration: \(finalDuration)")
//            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
//                guard let self = self else { return }
//                self.flutterChannel?.invokeMethod("onCallEnded", arguments: [
//                    "duration": finalDuration,
//                    "isOutgoing": true
//                ])
//                self.resetCallState()  // Reset state after call ends
//            }
//        }
//    }
//}
//
//// Extension to CXCall to check if it's outgoing
//extension CXCall {
//    var isOutgoing: Bool {
//        return hasConnected && !hasEnded
//    }
//}
