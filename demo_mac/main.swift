//
//  main.swift
//  demo_mac
//
//  Created by Nicholas Mosier on 6/2/17.
//  Copyright © 2017 Nicholas Mosier. All rights reserved.
//

import Foundation
import Cocoa
import CoreFoundation
import CocoaAsyncSocket
import AVFoundation

let app = NSApplication.shared()    // creates new shared application -- is necessary to create new windows
// will need to call NSApp.run() -> starts main event loop

var cameraServiceBrowser: CameraServiceBrowser!
var photoReceiver: PhotoReceiver!
var displayController: DisplayController!

let bracketCount = 10
var bracketNumber = 0

func getBracketSpecs() {
    print("Resolution:\t", terminator: "")
    let sessionPreset = readLine(strippingNewline: true)!
    print("Exposure settings:\t", terminator: "")
    let exposureInput = readLine(strippingNewline: true)!
    let photoCount = exposureInput.characters.split(separator: " ")
    let exposures = photoCount.map {
        Double(String($0))!
    }
    captureNextBracket(captureSessionPreset: sessionPreset, exposureTimes: exposures)
}

func captureNextBracket(captureSessionPreset: String, exposureTimes: [Double]) {
    guard cameraServiceBrowser.readyToSendPacket else {
        return
    }
    
    if bracketNumber >= bracketCount {
        return
    }
    
    let image = displayController.createCGImage(filePath: "/Users/nicholas/Desktop/display_images/\(bracketNumber%2).jpg")
    displayController.windows.first!.image = image
    displayController.windows.first!.drawImage(image)
    
    let cameraInstructionPacket = CameraInstructionPacket(cameraInstruction: .CapturePhotoBracket, captureSessionPreset: captureSessionPreset, photoBracketExposures: exposureTimes)
    cameraServiceBrowser.sendPacket(cameraInstructionPacket)
    
    photoReceiver.receivePhotoBracket(name: "bracket\(bracketNumber)", photoCount: exposureTimes.count, completionHandler: getBracketSpecs)
    bracketNumber += 1
}

var focusCount = 0
var focusLimit = 10
func captureNextFocus() {
    guard cameraServiceBrowser.readyToSendPacket else {
        return
    }
    
    if focusCount >= focusLimit {
        return
    }
    
    let image = displayController.createCGImage(filePath: "/Users/nicholas/Desktop/display_images/\(bracketNumber%2).jpg")
    displayController.windows.first!.image = image
    displayController.windows.first!.drawImage(image)
    
    let pointOfFocus = CGPoint(x: Double(focusCount+1)/Double(focusLimit+1), y: Double(focusCount+1)/Double(focusLimit+1))
    let packet = CameraInstructionPacket(cameraInstruction: .CaptureStillImage, captureSessionPreset: "high", pointOfFocus: pointOfFocus, torchMode: .on, torchLevel: Float(focusCount+1)/Float(focusLimit+1))
    cameraServiceBrowser.sendPacket(packet)
    
    photoReceiver.receivePhotoBracket(name: "focus\(focusCount)", photoCount: 1, completionHandler: captureNextFocus)
    focusCount += 1
}

displayController = DisplayController()
guard NSScreen.screens()!.count > 1  else {
    print("Only one screen connected.")
    fatalError()
}

for screen in NSScreen.screens()! {
    if screen != NSScreen.main()! {
        displayController.createNewWindow(on: screen)
    }
}

let binaryCodeQueue = DispatchQueue(label: "test")
displayController.windows.first!.configureDisplaySettings(horizontal: false, inverted: false)
displayController.windows.first!.displayBinaryCode(forBit: 8, system: .GrayCode)
//displayController.windows.first!.displayBinaryCode(forBit: 9, system: .MinStripeWidthCode)



// test drawing bitmap

cameraServiceBrowser = CameraServiceBrowser()
photoReceiver = PhotoReceiver()

photoReceiver.startBroadcast()
cameraServiceBrowser.startBrowsing()


let instructionInputQueue = DispatchQueue(label: "com.demo.instructionInputQueue")
instructionInputQueue.async {
    while !cameraServiceBrowser.readyToSendPacket {}
    
    captureNextFocus()
}
NSApp.run()
