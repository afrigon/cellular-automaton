//
//  DisplayLink.swift
//  MetalMac
//
//  Created by Jose Canepa on 8/18/16.
//  Edited by Alexandre Frigon on 10/15/18.
//  Copyright © 2016 Jose Canepa. All rights reserved.
//

import AppKit

/**
 Analog to the CADisplayLink in iOS.
 */
class DisplayLink {
    let timer  : CVDisplayLink
    let source : DispatchSourceUserDataAdd
    var callback : Optional<() -> ()> = nil
    var running : Bool { return CVDisplayLinkIsRunning(timer) }
    
    /**
     Creates a new DisplayLink that gets executed on the given queue
     
     - Parameters:
     - queue: Queue which will receive the callback calls
     */
    init?(onQueue queue: DispatchQueue = DispatchQueue.main) {
        self.source = DispatchSource.makeUserDataAddSource(queue: queue)
        var timerRef : CVDisplayLink? = nil
        var successLink = CVDisplayLinkCreateWithActiveCGDisplays(&timerRef)
        
        guard let timer = timerRef else {
            NSLog("Failed to create timer with active display")
            return nil
        }
        
        // Set Output
        successLink = CVDisplayLinkSetOutputCallback(timer, { (timer : CVDisplayLink, currentTime : UnsafePointer<CVTimeStamp>, outputTime : UnsafePointer<CVTimeStamp>, _ : CVOptionFlags, _ : UnsafeMutablePointer<CVOptionFlags>, sourceUnsafeRaw : UnsafeMutableRawPointer?) -> CVReturn in
            // Un-opaque the source
            if let sourceUnsafeRaw = sourceUnsafeRaw {
                // Update the value of the source, thus, triggering a handle call on the timer
                let sourceUnmanaged = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(sourceUnsafeRaw)
                sourceUnmanaged.takeUnretainedValue().add(data: 1)
            }
            
            return kCVReturnSuccess
                                                        
        }, Unmanaged.passUnretained(self.source).toOpaque())
        guard successLink == kCVReturnSuccess else {
            NSLog("Failed to create timer with active display")
            return nil
        }
        
        // Connect to display
        successLink = CVDisplayLinkSetCurrentCGDisplay(timer, CGMainDisplayID())
        guard successLink == kCVReturnSuccess else {
            NSLog("Failed to connect to display")
            return nil
        }
        
        self.timer = timer
        self.source.setEventHandler(handler: { [weak self] in self?.callback?() })
    }
    
    public func start() {
        guard !self.running else { return }
        
        CVDisplayLinkStart(self.timer)
        self.source.resume()
    }
    
    public func suspend() {
        guard self.running else { return }
        CVDisplayLinkStop(self.timer)
        self.source.suspend()
    }
    
    deinit {
        if self.running { self.suspend() }
    }
}
