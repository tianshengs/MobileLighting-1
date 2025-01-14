//
// ProgramControl.swift
// MobileLighting_Mac
//
// Contains central functions to the program, i.e. setting the camera focus, etc.. Manages these via
// the Command enum for use in CLT format.
//

import Foundation
import Cocoa
import VXMCtrl
import SwitcherCtrl
import Yaml
import AVFoundation


//MARK: COMMAND-LINE INPUT

// Enum for all commands
enum Command: String, EnumCollection, CaseIterable {      // rawValues are automatically the name of the case, i.e. .help.rawValue == "help" (useful for ensuring the command-handling switch statement is exhaustive)
    case help
    case unrecognized
    case quit
    case reloadsettings
    
    case struclight
    case takeamb
    
    // camera settings
    case readfocus, autofocus, setfocus, lockfocus
    case readexposure, autoexposure, lockexposure, setexposure
    case lockwhitebalance
    case focuspoint
    case cb     // displays checkerboard
    case black, white
    case diagonal, verticalbars   // displays diagonal stripes (for testing 'diagonal' DLP chip)
    
    // communications & serial control
    case connect
    case disconnect, disconnectall
    case proj
    
    // robot control
    case loadpath
    case movearm
    
    // image processing
    case refine
    case rectify
    case disparity
    case merge
    case reproject
    case merge2
    
    // camera calibration
    case calibrate  // 'x'
    case calibrate2pos
    case stereocalib
    case getintrinsics
    case getextrinsics
    
    // take ambient photos
    
    // for debugging
    case dispres
    case dispcode
    case clearpackets
    
    // for scripting
    case sleep
}

// Return usage message for appropriate command
func getUsage(_ command: Command) -> String {
    switch command {
    case .unrecognized: return "Command unrecognized. Type \"help\" for a list of commands."
    case .help: return "help [command name]?"
    case .quit: return "quit"
    case .reloadsettings: return "reloadsettings"
    case .connect: return "connect (switcher|vxm) [/dev/tty*Repleo*]"
    case .disconnect: return "disconnect (switcher|vxm)"
    case .disconnectall: return "disconnectall"
    case .calibrate: return "calibrate (-d|-a)?\n       -d: delete existing photos\n       -a: append to existing photos"
    case .calibrate2pos: return "calibrate2pos [leftPos: Int] [rightPos: Int] [photosCountPerPos: Int] [resolution=high]"
    case .stereocalib: return "stereocalib [nPhotos: Int] [resolution=high]"
    case .struclight: return "struclight [id] [projector #] [position #] [resolution=high]"
    case .takeamb: return "takeamb still (-f|-t)? [resolution=high]\n       takeamb video (-f|-t)? [exposure#=1]"
    case .readfocus: return "readfocus"
    case .autofocus: return "autofocus"
    case .lockfocus: return "lockfocus"
    case .setfocus: return "setfocus [lensPosition s.t. 0≤ l.p. ≤1]"
    case .focuspoint: return "focuspoint [x_coord] [y_coord]"
    case .lockwhitebalance: return "lockwhitebalance"
    case .readexposure: return "readexposure"
    case .autoexposure: return "autoexposure"
    case .lockexposure: return "lockexposure"
    case .setexposure: return "setexposure [exposureDuration] [exposureISO]\n       (set either parameter to 0 to leave unchanged)"
    case .cb: return "cb [squareSize=2]"
    case .black: return "black"
    case .white: return "white"
    case .diagonal: return "diagonal [stripe width]"
    case .verticalbars: return "verticalbars [width]"
    case .loadpath: return "loadpath [pathname]"
    case .movearm: return "movearm [posID]\n        [pose/joint string]\n       (x|y|z) [dist]"
    case .proj: return "proj ([projector_#]|all) (on/1|off/0)"
    case .refine: return "refine    [proj]    [pos]\nrefine    -a    [pos]\nrefine    -a    -a\nrefine  -r    [proj]    [left] [right]\nrefine     -r    -a    [left] [right]\nrefine    -r    -a    -a"
    case .disparity: return "disparity (-r)? [proj] [left] [right]\n       disparity (-r)?   -a   [left] [right]\n       disparity (-r)?   -a   -a"
    case .rectify: return "rectify [proj] [left] [right]\n       rectify   -a   [left] [right]\n       rectify   -a    -a"
    case .merge: return "merge (-r)? [left] [right]\n       merge (-r)?  -a"
    case .reproject: return "reproject [left] [right]\n       reproject -a"
    case .merge2: return "merge2 [left] [right]\n       merge2 -a"
    case .getintrinsics: return "getintrinsics"
    case .getextrinsics: return "getextrinsics [leftpos] [rightpos]\ngetextrinsics -a"
    case .dispres: return "dispres"
    case .dispcode: return "dispcode"
    case .sleep: return "sleep [secs: Float]"
    case .clearpackets: return "clearpackets"
    }
}


var processingCommand: Bool = false

// nextCommand: prompts for next command at command line, then handles command
// -Return value -> true if program should continue, false if should exit
func nextCommand() -> Bool {
    print("> ", terminator: "")
    guard let input = readLine(strippingNewline: true) else {
        // if input empty, simply return & continue execution
        return true
    }
    return processCommand(input)
}

func processCommand(_ input: String) -> Bool {
    var nextToken = 0
    let tokens: [String] = input.split(separator: " ").map{ return String($0) }
    let command: Command
    if let command_ = Command(rawValue: tokens.first ?? "") { // "" is invalid token, automatically rejected
        // if input contains no valid commands, return
        command = command_
    } else {
        command = .unrecognized
    }
    let usage = "usage: \t\(getUsage(command))"
    
    processingCommand = true
    
    nextToken += 1
    cmdSwitch: switch command {
    case .unrecognized:
        print(usage)
        break
        
    case .help:
        switch tokens.count {
        case 1:
            // print all commands & usage
            for command in Command.allCases {
                print("\(command):\t\(getUsage(command))")
            }
        case 2:
            if let command = Command(rawValue: tokens[1]) {
                print("\(command):\n\(getUsage(command))")
            } else {
                print("Command \(tokens[1]) unrecognized. Enter 'help' for a list of commands")
            }
        default:
            print(usage)
        }
        
    case .quit:
        return false
        
    case .reloadsettings:
        // rereads init settings file and reloads attributes
        guard tokens.count == 1 else {
            print(usage)
            break
        }
        do {
            sceneSettings = try SceneSettings(sceneSettingsPath)
            print("Successfully loaded initial settings.")
            strucExposureDurations = sceneSettings.strucExposureDurations
            strucExposureISOs = sceneSettings.strucExposureISOs
            if let calibDuration = sceneSettings.calibrationExposureDuration, let calibISO = sceneSettings.calibrationExposureISO {
                calibrationExposure = (calibDuration, calibISO)
            }
            trajectory = sceneSettings.trajectory
        } catch let error {
            print("Fatal error: could not load init settings, \(error.localizedDescription)")
            break
        }
        
    // connect: use to connect external devices
    case .connect:
        guard tokens.count >= 2 else {
            print(usage)
            break
        }
        
        switch tokens[1] {
        case "iphone":
            initializeIPhoneCommunications()
            
        case "switcher":
            guard tokens.count == 3 else {
                print("usage: connect switcher: must specify port (e.g. /dev/cu.usbserial\n(hint: ls /dev/cu.*)")
                break
            }
            displayController.switcher = Switcher(portName: tokens[2])
            displayController.switcher!.startConnection()
            
        case "vxm":
            guard tokens.count == 3 else {
                print("connect vxm: must specify port (e.g. /dev/cu.usbserial\n(hint: ls /dev/cu.*)")
                break
            }
            vxmController = VXMController(portName: tokens[2])
            _ = vxmController.startVXM()
            
        case "display":
            guard tokens.count == 2 else {
                print("connect display takes no additional arguments.")
                break
            }
            guard configureDisplays() else {
                print("connect display: failed to configure display.")
                break
            }
            print("connect display: successfully configured display.")
        default:
            print("cannot connect: invalid device name.")
        }
        
    // disconnect: use to disconnect vxm or switcher (generally not necessary)
    case .disconnect:
        guard tokens.count == 2 else {
            print(usage)
            break
        }
        
        switch tokens[1] {
        case "vxm":
            vxmController.stop()
        case "switcher":
            if let switcher = displayController.switcher {
                switcher.endConnection()
            }
        default:
            print("connect: invalid device \(tokens[1])")
            break
        }
        
    // disconnects both switcher and vxm box
    case .disconnectall:
        vxmController.stop()
        displayController.switcher?.endConnection()
        
    // takes specified number of calibration images; saves them to (scene)/orig/calibration/other
    case .calibrate:
        guard tokens.count == 1 || tokens.count == 2 else {
            print(usage)
            break
        }
        
        // Set exposure and ISOs
        if calibrationExposure != (0, 0) {
            let packet = CameraInstructionPacket(cameraInstruction: .SetExposure, photoBracketExposureDurations: [calibrationExposure.0], photoBracketExposureISOs: [calibrationExposure.1])
            cameraServiceBrowser.sendPacket(packet)
        }
        
        let nPhotos: Int
        let startIndex: Int
        if tokens.count == 2 {
            let mode = tokens[1]
            guard ["-d","-a"].contains(mode) else {
                print("calibrate: unrecognized flag \(mode)")
                break
            }
            var photos = (try! FileManager.default.contentsOfDirectory(atPath: dirStruc.intrinsicsPhotos)).map {
                return "\(dirStruc.intrinsicsPhotos)/\($0)"
            }
            switch mode {
            case "-d":
                for photo in photos {
                    do { try FileManager.default.removeItem(atPath: photo) }
                    catch { print("could not remove \(photo)") }
                }
                startIndex = 0
            case "-a":
                photos = photos.map{
                    return String($0.split(separator: "/").last!)
                }
                let ids: [Int] = photos.map{
                    guard $0.hasPrefix("IMG"), $0.hasSuffix(".JPG"), let id = Int($0.dropFirst(3).dropLast(4)) else {
                        return -1
                    }
                    return id
                }
                startIndex = ids.max()! + 1
            default:
                startIndex = 0
            }
        } else {
            startIndex = 0
        }
        let packet = CameraInstructionPacket(cameraInstruction: .CaptureStillImage, resolution: defaultResolution)
        let subpath = dirStruc.intrinsicsPhotos
        
        // Insert photos starting at the right index, stopping on user prompt
        var i: Int = startIndex;
        while(true) {
            print("Hit enter to take a photo or write q to finish taking photos.")
            guard let input = readLine() else {
                fatalError("Unexpected error in reading stdin.")
            }
            if ["q", "quit"].contains(input) {
                break
            }
            
            // take calibration photo
            var receivedCalibrationImage = false
            cameraServiceBrowser.sendPacket(packet)
            let completionHandler = { receivedCalibrationImage = true }
            photoReceiver.dataReceivers.insertFirst(
                CalibrationImageReceiver(completionHandler, dir: subpath, id: i)
            )
            while !receivedCalibrationImage {}
            print("\n\(i-startIndex+1) photos recorded.")
            i += 1
        }
        break
        
        // captures calibration images from two viewpoints
        // viewpoints specified as integers corresponding to the position along the linear
        //    robot arm's axis
        // NOTE: requires user to hit 'enter' to indicate robot arm has finished moving to
    //     proper location
    case .calibrate2pos:
        guard tokens.count >= 4 && tokens.count <= 5 else {
            print(usage)
            break
        }
        guard let left = Int(tokens[1]),
            let right = Int(tokens[2]),
            let nPhotos = Int(tokens[3]),
            nPhotos > 0 else {
                print("calibrate2pos: invalid argument(s).")
                break
        }
        
        if calibrationExposure != (0, 0) {
            let packet = CameraInstructionPacket(cameraInstruction: .SetExposure, photoBracketExposureDurations: [calibrationExposure.0], photoBracketExposureISOs: [calibrationExposure.1])
            cameraServiceBrowser.sendPacket(packet)
        }
        
        let resolution = (tokens.count == 5) ? tokens[4] : defaultResolution   // high is default res
        captureStereoCalibration(left: left, right: right, nPhotos: nPhotos, resolution: resolution)
        break
        
    case .stereocalib:
        let (params, flags) = partitionTokens([String](tokens[1...]))
        // Make sure we have the right number of tokens
        guard params.count <= 1, flags.count <= 1 else {
            print(usage)
            break
        }
        
        // Get resolution
        let resolution: String
        if params.count == 1 {
            resolution = params[0]
        } else {
            resolution = defaultResolution
        }
        
        var mode: String = "default"; // Arbitrary initialization
        // Get optional flag
        if flags.count == 1 {
            mode = flags[0]
        }
        
        var appending = false
        for flag in flags {
            switch flag {
            case "-a":
                print("stereocalib: appending images.")
                appending = true
            default:
                print("stereocalib: unrecognized flag \(flag).")
            }
        }
        
        if calibrationExposure != (0, 0) {
            let packet = CameraInstructionPacket(cameraInstruction: .SetExposure, photoBracketExposureDurations: [calibrationExposure.0], photoBracketExposureISOs: [calibrationExposure.1])
            cameraServiceBrowser.sendPacket(packet)
        }
        
        let posIDs = [Int](0..<positions.count)
        captureNPosCalibration(posIDs: posIDs, resolution: resolution, mode: mode)
        break
        
    // captures scene using structured lighting from specified projector and position number
    // - code system to use is an optional parameter: can either be 'gray' or 'minSW' (default is 'minSW')
    //  NOTE: this command does not move the arm; it must already be in the correct positions
    //      BUT it does configure the projectors
    case .struclight:
        let system: BinaryCodeSystem
        
        guard tokens.count >= 4 else {
            print(usage)
            break
        }
        guard let projPos = Int(tokens[1]) else {
            print("struclight: invalid projector position number")
            break
        }
        guard let projID = Int(tokens[2]) else {
            print("struclight: invalid projector id.")
            break
        }
        guard let armPos = Int(tokens[3]) else {
            print("struclight: invalid position number \(tokens[2]).")
            break
        }
        guard armPos >= 0, armPos < positions.count else {
            print("struclight: position \(armPos) out of range.")
            break
        }
        
        // currentPos = armPos       // update current position
        // currentProj = projPos     // update current projector
        
        system = .MinStripeWidthCode
        
        let resolution: String
        if tokens.count == 5 {
            resolution = tokens[4]
        } else {
            resolution = defaultResolution
        }
        
        displayController.switcher?.turnOff(0)   // turns off all projs
        print("Hit enter when all projectors off.")
        _ = readLine()  // wait until user hits enter
        displayController.switcher?.turnOn(projID)
        print("Hit enter when selected projector ready.") // Turn on the selected projector
        _ = readLine()  // wait until user hits enter
        
        // Tell the Rosvita server to move the arm to the selected position
        var posStr = *String(armPos) // get pointer to pose string
        GotoView(&posStr) // pass address of pointer
        usleep(UInt32(robotDelay * 1.0e6)) // pause for a moment
        
        captureWithStructuredLighting(system: system, projector: projPos, position: armPos, resolution: resolution)
        break
        
        
    case .takeamb:
        let (params, flags) = partitionTokens([String](tokens[1...]))
        
        guard params.count >= 1 else {
            print(usage)
            break
        }
        
        switch params[0] {
        case "still":
            guard params.count >= 1 else {
                print("usage: takeamb still [resolution]?")
                break cmdSwitch
            }
            
            let resolution: String
            if params.count == 2 {
                resolution = params[1]
            } else {
                resolution = defaultResolution
            }
            
            var mode = DirectoryStructure.PhotoMode.normal
            var flashMode = AVCaptureDevice.FlashMode.off
            var torchMode = AVCaptureDevice.TorchMode.off
            for flag in flags {
                switch flag {
                case "-f":
                    print("takeamb still: using flash mode...")
                    flashMode = .on
                    mode = .flash
                case "-t":
                    print("takeamb still: using torch mode...")
                    mode = .torch
                    torchMode = .on
                default:
                    print("takeamb still: flag \(flag) not recognized.")
                }
            }
                        
            let packet = CameraInstructionPacket(cameraInstruction: .CapturePhotoBracket, resolution: resolution, photoBracketExposureDurations: sceneSettings.ambientExposureDurations, torchMode: torchMode, flashMode: flashMode, photoBracketExposureISOs: sceneSettings.ambientExposureISOs)
            
            // Move the robot to the correct position and prompt photo capture
            for pos in 0..<positions.count {
                var posStr = *String(pos)
                GotoView(&posStr)
                usleep(UInt32(robotDelay * 1.0e6)) // pause for a moment
            
                // take photo bracket
                cameraServiceBrowser.sendPacket(packet)
                
                func receivePhotos() {
                    var nReceived = 0
                    let completionHandler = { nReceived += 1 }
                    for exp in 0..<sceneSettings.ambientExposureDurations!.count {
                        let path = dirStruc.ambientPhotos(pos: pos, exp: exp, mode: mode) + "/IMG\(exp).JPG"
                        let ambReceiver = AmbientImageReceiver(completionHandler, path: path)
                        photoReceiver.dataReceivers.insertFirst(ambReceiver)
                    }
                    while nReceived != sceneSettings.ambientExposureDurations!.count {}
                }
                
                switch mode {
                case .flash:
                    var received = false
                    let completionHandler = { received = true }
                    let path = dirStruc.ambientPhotos(pos: pos, mode: .flash) + "/IMG.JPG"
                    let ambReceiver = AmbientImageReceiver(completionHandler, path: path)
                    photoReceiver.dataReceivers.insertFirst(ambReceiver)
                    while !received {}
                    break
                    
                case .torch:
                    let torchPacket = CameraInstructionPacket(cameraInstruction: .ConfigureTorchMode, torchMode: .on, torchLevel: torchModeLevel)
                    cameraServiceBrowser.sendPacket(torchPacket)
                    receivePhotos()
                    torchPacket.torchMode = .off
                    torchPacket.torchLevel = nil
                    cameraServiceBrowser.sendPacket(torchPacket)
                    break
                    
                case .normal:
                    receivePhotos()
                    break
                }
            }
            
            break
            
        case "video":
            guard params.count >= 1, params.count <= 2 else {
                print(usage)
                break cmdSwitch
            }
            
            let exp: Int
            if params.count == 1 {
                exp = min(sceneSettings.ambientExposureDurations?.count ?? -1, sceneSettings.ambientExposureISOs?.count ?? -1) / 2
            } else {
                guard let exp_ = Int(params[1]), exp_ >= 0, exp_ < min(sceneSettings.ambientExposureDurations?.count ?? -1, sceneSettings.ambientExposureISOs?.count ?? -1) else {
                    print("takeamb video: invalid exposure number \(params[1])")
                    break cmdSwitch
                }
                exp = exp_
            }
            
            var torchMode: AVCaptureDevice.TorchMode = .off
            var mode: DirectoryStructure.VideoMode = .normal
            for flag in flags {
                switch flag {
                case "-f", "-t":
                    print("takeamb video: using torch mode.")
                    torchMode = .on
                    mode = .torch
                default:
                    print("takeamb video: flag \(flag) not recognized.")
                }
            }
            
            trajectory.moveToStart()
            print("takeamb video: hit enter when camera in position.")
            _ = readLine()
            
            print("takeamb video: starting recording...")
            var packet = CameraInstructionPacket(cameraInstruction: .StartVideoCapture, photoBracketExposureDurations: [sceneSettings.ambientExposureDurations![exp]], torchMode: torchMode, photoBracketExposureISOs: [sceneSettings.ambientExposureISOs![exp]])
            cameraServiceBrowser.sendPacket(packet)
            
            usleep(UInt32(0.5 * 1e6)) // wait 0.5 seconds
            
            // configure video data receiver
            let videoReceiver = AmbientVideoReceiver({}, path: "\(dirStruc.ambientVideos(exp: exp, mode: mode))/video.mp4")
            photoReceiver.dataReceivers.insertFirst(videoReceiver)
            let imuReceiver = IMUDataReceiver({}, path: "\(dirStruc.ambientVideos(exp: exp, mode: mode))/imu.yml")
            photoReceiver.dataReceivers.insertFirst(imuReceiver)
            
            trajectory.executeScript()
            print("takeamb video: hit enter when trajectory completed.")
            _ = readLine()
            packet = CameraInstructionPacket(cameraInstruction: .EndVideoCapture)
            cameraServiceBrowser.sendPacket(packet)
            print("takeamb video: stopping recording.")
            
            break
        default:
            break
        }
        
        break
        
        
        
    // requests current lens position from iPhone camera, prints it
    case .readfocus:
        let packet = CameraInstructionPacket(cameraInstruction: .GetLensPosition)
        cameraServiceBrowser.sendPacket(packet)
        
        photoReceiver.dataReceivers.insertFirst(
            LensPositionReceiver { (pos: Float) in
                print("Lens position:\t\(pos)")
                processingCommand = false
            }
        )
        
    // tells the iPhone to use the 'auto focus' focus mode
    case .autofocus:
        _ = setLensPosition(-1.0)
        processingCommand = false
        
    // tells the iPhone to lock the focus at the current position
    case .lockfocus:
        let packet = CameraInstructionPacket(cameraInstruction: .LockLensPosition)
        cameraServiceBrowser.sendPacket(packet)
        _ = photoReceiver.receiveLensPositionSync()
        
    // tells the iPhone to set the focus to the given lens position & lock the focus
    case .setfocus:
        guard nextToken < tokens.count else {
            //            print("usage: setfocus [lensPosition] (0.0 <= lensPosition <= 1.0)")
            print(usage)
            break
        }
        guard let pos = Float(tokens[nextToken]) else {
            print("ERROR: Could not parse float value for lens position.")
            break
        }
        _ = setLensPosition(pos)
        processingCommand = false
        
        // autofocus on point, given in normalized x and y coordinates
    // NOTE: top left corner of image frame when iPhone is held in landscape with home button on the right corresponds to (0.0, 0.0).
    case .focuspoint:
        // arguments: x coord then y coord (0.0 <= 1.0, 0.0 <= 1.0)
        guard tokens.count >= 3 else {
            //            print("usage: focuspoint [x_coord] [y_coord]")
            print(usage)
            break
        }
        guard let x = Float(tokens[1]), let y = Float(tokens[2]) else {
            print("invalid x or y coordinate: must be on interval [0.0, 1.0]")
            break
        }
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let packet = CameraInstructionPacket(cameraInstruction: .SetPointOfFocus, pointOfFocus: point)
        cameraServiceBrowser.sendPacket(packet)
        _ = photoReceiver.receiveLensPositionSync()
        break
        
    // currently useless, but leaving in here just in case it ever comes in handy
    case .lockwhitebalance:
        let packet = CameraInstructionPacket(cameraInstruction: .LockWhiteBalance)
        cameraServiceBrowser.sendPacket(packet)
        var receivedUpdate = false
        photoReceiver.dataReceivers.insertFirst(
            StatusUpdateReceiver { (update: CameraStatusUpdate) in
                receivedUpdate = true
            }
        )
        while !receivedUpdate {}
        
    // tells iphone to send current exposure duration & ISO
    case .readexposure:
        let packet = CameraInstructionPacket(cameraInstruction: .ReadExposure)
        cameraServiceBrowser.sendPacket(packet)
        let completionHandler = { (exposure: (Double, Float)) -> Void in
            print("exposure duration = \(exposure.0), iso = \(exposure.1)")
        }
        photoReceiver.dataReceivers.insertFirst(ExposureReceiver(completionHandler))
        
    // tells iPhone to use auto exposure mode (automatically adjusts exposure)
    case .autoexposure:
        let packet = CameraInstructionPacket(cameraInstruction: .AutoExposure)
        cameraServiceBrowser.sendPacket(packet)
        
        // tells iPhone to use locked exposure mode (does not change exposure settings, even when lighting changes)
    case .lockexposure:
        let packet = CameraInstructionPacket(cameraInstruction: .LockExposure)
        cameraServiceBrowser.sendPacket(packet)
        
    case .setexposure:
        guard tokens.count == 3 else {
            print(usage)
            break
        }
        guard let exposureDuration = Double(tokens[1]), let exposureISO = Float(tokens[2]) else {
            print("setexposure: invalid parameters \(tokens[1]), \(tokens[2])")
            break
        }
        let packet = CameraInstructionPacket(cameraInstruction: .SetExposure, photoBracketExposureDurations: [exposureDuration], photoBracketExposureISOs: [Double(exposureISO)])
        cameraServiceBrowser.sendPacket(packet)
        
        // displays checkerboard pattern
    // optional parameter: side length of squares, in pixels
    case .cb:
        //        let usage = "usage: cb [squareSize]?"
        let size: Int
        guard tokens.count >= 1 && tokens.count <= 2 else {
            print(usage)
            break
        }
        if tokens.count == 2 {
            size = Int(tokens[nextToken]) ?? 2
        } else {
            size = 2
        }
        displayController.currentWindow?.displayCheckerboard(squareSize: size)
        break
        
    // paints entire window black
    case .black:
        displayController.currentWindow?.displayBlack()
        break
        
    // paints entire window white
    case .white:
        displayController.currentWindow?.displayWhite()
        break
        
        // displays diagonal stripes (at 45°) of specified width (measured horizontally)
    // (tool for testing pico projector and its diagonal pixel grid)
    case .diagonal:
        guard tokens.count == 2, let stripeWidth = Int(tokens[1]) else {
            print(usage)
            break
        }
        displayController.currentWindow?.displayDiagonal(width: stripeWidth)
        break
        
        // displays vertical bars of specified width
    // (tool originaly made for testing pico projector)
    case .verticalbars:
        guard tokens.count == 2, let stripeWidth = Int(tokens[1]) else {
            print(usage)
            break
        }
        displayController.currentWindow?.displayVertical(width: stripeWidth)
        break
        
    // Select the appropriate robot arm path for the Rosvita server to load
    case .loadpath:
        guard tokens.count == 2 else {
            print(usage)
            break
        }
        
        let path: String = tokens[1] // the first argument should specify a pathname
        var pathPointer = *path // get pointer to the string
        var status = LoadPath(&pathPointer) // load the path with "pathname" on Rosvita server
        if status != 0 { // print a message if the LoadPath doesn't return 0
            print("Could not load path \"\(path)\"")
        }
        break
        
    // moves linear robot arm to specified position using VXM controller box
    //   *the specified position can be either an integer or 'MIN'/'MAX', where 'MIN' resets the arm
    //      (and zeroes out the coordinate system)*
    case .movearm:
        switch tokens.count {
        case 2:
            let posStr: String
            if let posID = Int(tokens[1]) {
                posStr = positions[posID]
            } else if tokens[1].hasPrefix("p[") && tokens[1].hasSuffix("]") {
                posStr = tokens[1]
            } else {
                print("movearm: \(tokens[1]) is not a valid position string or index.")
                break
            }
            print("Moving arm to position \(posStr)")
            var cStr = posStr.cString(using: .ascii)!
            DispatchQueue.main.async {
                // Tell the Rosvita server to move the arm to the selected position
                GotoView(&cStr)
                print("Moved arm to position \(posStr)")
            }
        case 3:
            guard let ds = Float(tokens[2]) else {
                print("movearm: \(tokens[2]) is not a valid distance.")
                break
            }
            switch tokens[1] {
            case "x":
                DispatchQueue.main.async {
//                    MoveLinearX(ds, 0, 0)
                }
            case "y":
                DispatchQueue.main.async {
//                    MoveLinearY(ds, 0, 0)
                }
            case "z":
                DispatchQueue.main.async {
//                    MoveLinearZ(ds, 0, 0)
                }
            default:
                print("moevarm: \(tokens[1]) is not a recognized direction.")
            }
            
        default:
            print(usage)
            break
        }
        
        break
        
        // used to turn projectors on or off
        //  -argument 1: either projector # (1–8) or 'all', which addresses all of them at once
        //  -argument 2: either 'on', 'off', '1', or '0', where '1' turns the respective projector(s) on
    // NOTE: the Kramer switcher box must be connected (use 'connect switcher' command), of course
    case .proj:
        guard tokens.count == 3 else {
            print(usage)
            break
        }
        if let projector = Int(tokens[1]) {
            switch tokens[2] {
            case "on", "1":
                displayController.switcher?.turnOn(projector)
            case "off", "0":
                displayController.switcher?.turnOff(projector)
            default:
                print("Unrecognized argument: \(tokens[2])")
            }
        } else if tokens[1] == "all" {
            switch tokens[2] {
            case "on", "1":
                displayController.switcher?.turnOn(0)
            case "off", "0":
                displayController.switcher?.turnOff(0)
            default:
                print("Unrecognized argument: \(tokens[2])")
            }
        } else {
            print("Not a valid projector number: \(tokens[1])")
        }
        break
        
        // refines decoded PFM image with given name (assumed to be located in the decoded subdirectory)
        //  and saves intermediate and final results to refined subdirectory
        //    -direction argument specifies which axis to refine in, where 0 <-> x-axis
        // TO-DO: this does not take advantage of the ideal direction calculations performed at the new smart
    //  thresholding step
    case .refine:
        guard tokens.count > 1 else {
            print(usage)
            break cmdSwitch
        }
        let (params, flags) = partitionTokens([String](tokens[1...]))
        var curParam = 0
        
        var rectified = false, allproj = false, allpos = false
        for flag in flags {
            switch flag {
            case "-r":
                rectified = true
            case "-a":
                if !allproj {
                    allproj = true
                } else {
                    allpos = true
                }
            default:
                print("refine: invalid flag \(flag)")
                break cmdSwitch
            }
        }
        
        // verify proper # of tokens passed
        if allproj, allpos {
            guard params.count == 0 else {
                print(usage)
                break
            }
        } else if allproj {
            guard params.count == (rectified ? 2 : 1) else {
                print(usage)
                break
            }
        } else {
            guard params.count == (rectified ? 3 : 2) else {
                print(usage)
                break
            }
        }
        
        
        var projs = [Int]()
        if allproj {
            let projDirs = try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(rectified))
            projs = getIDs(projDirs, prefix: "proj", suffix: "")
        } else {
            guard let proj = Int(params[0]) else {
                print("refine: invalid projector \(params[0])")
                break
            }
            projs = [proj]
            curParam += 1
        }

        let singlePositions: [Int]?
        if !allpos {
            if !rectified {
                guard let pos = Int(params[curParam]) else {
                    print(usage)
                    break
                }
                singlePositions = [pos]
            } else {
                guard let left = Int(params[curParam]), let right = Int(params[curParam+1]) else {
                    print(usage)
                    break
                }
                singlePositions = [left, right]
            }
        } else {
            singlePositions = nil
        }
        
        for proj in projs {
            let positions: [Int]
            if !allpos {
                positions = singlePositions!
            } else {
                let positiondirs = try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(proj: proj, rectified: rectified))
                positions = getIDs(positiondirs, prefix: "pos", suffix: "").sorted()
            }
            
            if !rectified {
                for pos in positions {
                    for direction: Int32 in [0, 1] {
                        var imgpath = *"\(dirStruc.decoded(proj: proj, pos: pos, rectified: false))/result\(pos)\(direction == 0 ? "u" : "v")-0initial.pfm"
                        var outdir = *dirStruc.decoded(proj: proj, pos: pos, rectified: false)
                        let metadatapath = dirStruc.metadataFile(Int(direction), proj: proj, pos: pos)
                        do {
                            let metadataStr = try String(contentsOfFile: metadatapath)
                            let metadata: Yaml = try Yaml.load(metadataStr)
                            if let angle: Double = metadata.dictionary?["angle"]?.double {
                                var posID = *"\(pos)"
                                refineDecodedIm(&outdir, direction, &imgpath, angle, &posID)
                            }
                        } catch {
                            print("refine error: could not load metadata file \(metadatapath).")
                        }
                    }
                }
            } else {
                let positionPairs = zip(positions, positions[1...])
                for (leftpos, rightpos) in positionPairs {
                    for direction: Int in [0, 1] {
                        for pos in [leftpos, rightpos] {
                            var cimg = *"\(dirStruc.decoded(proj: proj, pos: pos, rectified: true))/result\(leftpos)\(rightpos)\(direction == 0 ? "u" : "v")-0rectified.pfm"
                            var coutdir = *dirStruc.decoded(proj: proj, pos: pos, rectified: true)
                            
                            let metadatapath = dirStruc.metadataFile(Int(direction), proj: proj, pos: pos)
                            do {
                                let metadataStr = try String(contentsOfFile: metadatapath)
                                let metadata: Yaml = try Yaml.load(metadataStr)
                                if let angle: Double = metadata.dictionary?["angle"]?.double {
                                    var posID = *"\(leftpos)\(rightpos)"
                                    refineDecodedIm(&coutdir, Int32(direction), &cimg, angle, &posID)
                                }
                            } catch {
                                print("refine error: could not load metadata file \(metadatapath).")
                            }
                            
                        }
                    }
                }
            }
        }
        
        
        // computes disparity maps from decoded & refined images; saves them to 'disparity' directories
        // usage options:
        //  -'disparity': computes disparities for all projectors & all consecutive positions
        //  -'disparity [projector #]': computes disparities for given projectors for all consecutive positions
    //  -'disparity [projector #] [leftPos] [rightPos]': computes disparity map for single viewpoint pair for specified projector
    case .disparity:
        let (params, flags) = partitionTokens([String](tokens[1...]))
        var curParam = 0
        
        var rectified = false
        var allproj = false, allpos = false
        for flag in flags {
            switch flag {
            case "-r":
                rectified = true
            case "-a":
                if !allproj {
                    allproj = true
                } else {
                    allpos = true
                }
            default:
                print("disparity: invalid flag \(flag)")
                break cmdSwitch
            }
        }
        
        if allproj, allpos {
            guard params.count == 0 else {
                print(usage)
                break
            }
        } else if allproj {
            guard params.count == 2 else {
                print(usage)
                break
            }
        } else {
            guard params.count == 3 else {
                print(usage)
                break
            }
        }
        
        var projs = [Int]()
        if !allproj {
            guard let proj = Int(params[curParam]) else {
                print("disparity: invalid projector \(params[curParam])")
                break
            }
            projs = [proj]
            curParam += 1
        } else {
            let projDirs = try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(rectified))
            projs = getIDs(projDirs, prefix: "proj", suffix: "")
        }
        
        for proj in projs {
            let positions: [Int]
            if !allpos {
                guard let leftpos = Int(params[curParam]), let rightpos = Int(params[curParam+1]) else {
                    print("disparity: invalid positions \(params[curParam]), \(params[curParam+1])")
                    break
                }
                positions = [leftpos, rightpos]
            } else {
                let positiondirs = try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(proj: proj, rectified: rectified))
                positions = getIDs(positiondirs, prefix: "pos", suffix: "").sorted()
            }
            
            for (leftpos, rightpos) in zip(positions, positions[1...]) {
                disparityMatch(proj: proj, leftpos: leftpos, rightpos: rightpos, rectified: rectified)
            }
        }
        
    case .rectify:
        let (params, flags) = partitionTokens([String](tokens[1...]))
        
        var allproj = false
        var allpos = false
        for flag in flags {
            switch flag {
            case "-a":
                if !allproj {
                    allproj = true
                } else {
                    allpos = true
                }
            default:
                print("rectify: invalid flag \(flag)")
                break cmdSwitch
            }
        }
        
        var curTok = 0
        let projIDs: [Int]
        if allproj {
            let projDirs = try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(false))
            projIDs = getIDs(projDirs, prefix: "proj", suffix: "")
        } else {
            guard params.count >= curTok+1 else {
                print(usage)
                break
            }
            guard let proj = Int(params[curTok]) else {
                print("rectify: unrecognized projector ID \(params[curTok])")
                break
            }
            projIDs = [proj]
            curTok += 1
        }
        
        let singlePosPair: (Int,Int)?
        if allpos {
            singlePosPair = nil
        } else {
            guard params.count == curTok + 2 else {
                print(usage)
                break
            }
            guard let left = Int(params[curTok]), let right = Int(params[curTok+1]) else {
                print("rectify: unrecognized positions \(params[curTok]), \(params[curTok+1])")
                break
            }
            singlePosPair = (left, right)
        }
        for proj in projIDs {
            let posIDpairs: [(Int,Int)]
            if allpos {
                var posIDs = getIDs(try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(proj: proj, rectified: false)), prefix: "pos", suffix: "")
                guard posIDs.count > 1 else {
                    print("rectify: skipping projectory \(proj), not enough positions.")
                    continue
                }
                posIDs.sort()
                posIDpairs = [(Int,Int)](zip(posIDs, posIDs[1...]))
            } else {
                posIDpairs = [singlePosPair!]
            }
            for (left, right) in posIDpairs {
                rectify(left: left, right: right, proj: proj)
            }
        }
        
    case .merge:
        let (params, flags) = partitionTokens([String](tokens[1...]))
        
        var rectified = false, allpos = false
        for flag in flags {
            switch flag {
            case "-r":
                rectified = true
            case "-a":
                allpos = true
            default:
                print("merge: unrecognized flag \(flag)")
                break
            }
        }
        
        let nparams: Int
        if allpos { nparams = 0 }
        else { nparams = 2 }
        guard params.count == nparams else {
            print(usage)
            break
        }
        
        let positions: [Int]
        if !allpos {
            guard let leftpos = Int(params[0]), let rightpos = Int(params[1]) else {
                print(usage)
                break
            }
            positions = [leftpos, rightpos]
        } else {
            var projdirs = (try! FileManager.default.contentsOfDirectory(atPath: dirStruc.disparity(rectified)))
            let projs = getIDs(projdirs, prefix: "proj", suffix: "")
            projdirs = projs.map {
                return dirStruc.disparity(proj: $0, rectified: rectified)
            }
            
            let positions2D: [[Int]] = projdirs.map {
                let positiondirs = try! FileManager.default.contentsOfDirectory(atPath: $0)
                let positions = getIDs(positiondirs, prefix: "pos", suffix: "")
                return positions
            }
            let posset = positions2D.reduce(Set<Int>(positions2D.first!)) { (set: Set<Int>, list: [Int]) in
                return set.intersection(list)
            }
            positions = [Int](posset).sorted()
        }
        
        for (left, right) in zip(positions, positions[1...]) {
            merge(left: left, right: right, rectified: rectified)
        }
        
    case .reproject:
        // implement -a functionality
        let (params, flags) = partitionTokens([String](tokens[1...]))
        
        var allpos = false
        for flag in flags {
            switch flag {
            case "-a":
                allpos = true
            default:
                print("reproject: unrecognized flag \(flag)")
                break
            }
        }
        
        let nparams: Int
        if allpos {
            nparams = 0
        } else {
            nparams = 2
        }
        guard params.count == nparams else {
            print(usage)
            break
        }
        
        let positions: [Int]
        if !allpos {
            guard let left = Int(params[0]), let right = Int(params[1]) else {
                print("reproject: invalid stereo position pair provided.")
                break
            }
            positions = [left, right]
        } else {
            var projdirs = (try! FileManager.default.contentsOfDirectory(atPath: dirStruc.decoded(true)))
            let projs = getIDs(projdirs, prefix: "proj", suffix: "")
            projdirs = projs.map {
                return dirStruc.decoded(proj: $0, rectified: true)
            }
            
            let positions2D: [[Int]] = projdirs.map {
                let positiondirs = try! FileManager.default.contentsOfDirectory(atPath: $0)
                let positions = getIDs(positiondirs, prefix: "pos", suffix: "")
                return positions
            }
            let posset = positions2D.reduce(Set<Int>(positions2D.first!)) { (set: Set<Int>, list: [Int]) in
                return set.intersection(list)
            }
            positions = [Int](posset).sorted()
        }
        
        for (left, right) in zip(positions, positions[1...]) {
            reproject(left: left, right: right)
        }
        
    case .merge2:
        let (params, flags) = partitionTokens([String](tokens[1...]))
        
        var allpos = false
        for flag in flags {
            switch flag {
            case "-a":
                allpos = true
            default:
                print("merge2: unrecognized flag \(flag).")
                break
            }
        }
        
        let nparams: Int
        if allpos { nparams = 0 }
        else { nparams = 2 }
        
        guard params.count == nparams else {
            print(usage)
            break
        }
        
        let positions: [Int]
        if !allpos {
            guard let left = Int(params[0]), let right = Int(params[1]) else {
                print("reproject: invalid stereo position pair provided.")
                break
            }
            positions = [left, right]
        } else {
            var projdirs = (try! FileManager.default.contentsOfDirectory(atPath: dirStruc.reprojected))
            let projs = getIDs(projdirs, prefix: "proj", suffix: "")
            projdirs = projs.map {
                return dirStruc.reprojected(proj: $0)
            }
            
            let positions2D: [[Int]] = projdirs.map {
                let positiondirs = try! FileManager.default.contentsOfDirectory(atPath: $0)
                let positions = getIDs(positiondirs, prefix: "pos", suffix: "")
                return positions
            }
            let posset = positions2D.reduce(Set<Int>(positions2D.first!)) { (set: Set<Int>, list: [Int]) in
                return set.intersection(list)
            }
            positions = [Int](posset).sorted()
        }
        
        for (left, right) in zip(positions, positions[1...]) {
            mergeReprojected(left: left, right: right)
        }
        
        // calculates camera's intrinsics using chessboard calibration photos in orig/calibration/chessboard
        // TO-DO: TEMPLATE PATHS SHOULD BE COPIED TO SAME DIRECTORY AS MAC EXECUTABLE SO
    // ABSOLUTE PATHS NOT REQUIRED
    case .getintrinsics:
        guard tokens.count <= 2 else {
            //            print("usage: \(commandUsage[command]!)")
            print(usage)
            break
        }
        let patternEnum: CalibrationSettings.CalibrationPattern
        if tokens.count == 1 {
            patternEnum = CalibrationSettings.CalibrationPattern.ARUCO_SINGLE
        } else {
            let pattern = tokens[1].uppercased()
            guard let patternEnumTemp = CalibrationSettings.CalibrationPattern(rawValue: pattern) else {
                print("getintrinsics: \(pattern) not recognized pattern.")
                break
            }
            patternEnum = patternEnumTemp
        }
        generateIntrinsicsImageList()
        let calib = CalibrationSettings(dirStruc.calibrationSettingsFile)
        
        calib.set(key: .Calibration_Pattern, value: Yaml.string(patternEnum.rawValue))
        calib.set(key: .Mode, value: Yaml.string(CalibrationSettings.CalibrationMode.INTRINSIC.rawValue))
        calib.set(key: .ImageList_Filename, value: Yaml.string(dirStruc.intrinsicsImageList))
        calib.set(key: .IntrinsicOutput_Filename, value: Yaml.string(dirStruc.intrinsicsYML))
        calib.save()
        var path = dirStruc.calibrationSettingsFile.cString(using: .ascii)!
        
        DispatchQueue.main.async {
            CalibrateWithSettings(&path)
        }
        break
        
    // do stereo calibration
    case .getextrinsics:
        let (params, flags) = partitionTokens(tokens)
        
        var all = false
        for flag in flags {
            switch flag {
            case "-a":
                all = true
                print("getextrinsics: computing extrinsics for all positions.")
            default:
                print("getextrinsics: unrecognized flag \(flag).")
            }
        }
        
        let positionPairs: [(Int, Int)]
        var curParam: Int
        if all {
            guard [1,2].contains(params.count) else {
                print(usage)
                break
            }
            let posIDs = [Int](0..<positions.count)
            positionPairs = [(Int,Int)](zip(posIDs, [Int](posIDs[1...])))
            curParam = 1
        } else {
            guard [3,4].contains(params.count), let pos0 = Int(params[1]), let pos1 = Int(params[2]) else {
                print(usage)
                break
            }
            positionPairs = [(pos0, pos1)]
            curParam = 3
        }
        
        let patternEnum: CalibrationSettings.CalibrationPattern
        if params.count > curParam {
            guard let patternEnum_ = CalibrationSettings.CalibrationPattern(rawValue: params[curParam]) else {
                print("getextrinsics: unrecognized board pattern \(params[curParam]).")
                break
            }
            patternEnum = patternEnum_
        } else {
            patternEnum = .ARUCO_SINGLE
        }
        
        for (leftpos, rightpos) in positionPairs {
            generateStereoImageList(left: dirStruc.stereoPhotos(leftpos), right: dirStruc.stereoPhotos(rightpos))
            
            let calib = CalibrationSettings(dirStruc.calibrationSettingsFile)
            calib.set(key: .Calibration_Pattern, value: Yaml.string(patternEnum.rawValue))
            calib.set(key: .Mode, value: Yaml.string("STEREO"))
            calib.set(key: .ImageList_Filename, value: Yaml.string(dirStruc.stereoImageList))
            calib.set(key: .ExtrinsicOutput_Filename, value: Yaml.string(dirStruc.extrinsicsYML(left: leftpos, right: rightpos)))
            calib.save()
            
            var path = *dirStruc.calibrationSettingsFile
            CalibrateWithSettings(&path)
        }
        
        // displays current resolution being used for external display
    // -useful for troubleshooting with projector display issues
    case .dispres:
        let screen = displayController.currentWindow!
        print("Screen resolution: \(screen.width)x\(screen.height)")
        
        // displays a min stripe width binary code pattern
    //  useful for verifying the minSW.dat file loaded properly
    case .dispcode:
        displayController.currentWindow!.displayBinaryCode(forBit: 0, system: .MinStripeWidthCode)
        
    // scripting
    case .sleep:
        guard tokens.count == 2 else {
            print(usage)
            break
        }
        guard let secs = Double(tokens[1]) else {
            print("sleep: \(tokens[1]) not a valid number of seconds.")
            break
        }
        usleep(UInt32(secs * 1000000))
        
    case .clearpackets:
        photoReceiver.dataReceivers.removeAll()
    }
    
    return true
}

/* The following extension could be implemented to suggest similar commands on unrecognized input,
 but is buggy:
 extension Command {
 init(closeTo unknown: String) {
 if let known = Command(rawValue: unknown) {
 self = known
 } else {
 // if command unrecognized, find closest match
 var cases: [String] = Command.cases().map { return $0.rawValue }
 // now D.P. solution
 let costs: [Int] = cases.map { (command: String) in
 var cache = [[Int]](repeating: [Int](repeating: 0, count: command.count+1), count: unknown.count+1)
 var runs = [[Int]](repeating: [Int](repeating:0, count: command.count+1), count: unknown.count+1)
 for i in 0..<command.count+1 {
 cache[0][i] = i
 }
 for j in 0..<unknown.count+1 {
 cache[j][0] = j
 }
 for j in 1..<unknown.count+1 {
 for i in 1..<command.count+1 {
 let cost = min(min(cache[j][i-1] + 1, cache[j-1][i] + 1), cache[j-1][i-1] + ((command[i-1] == unknown[j-1]) ? -runs[j-1][i-1] : 1) )
 cache[j][i] = cost
 switch cost {
 case cache[j][i-1] + 1:
 // zero out run
 runs[j][i] = 0
 case cache[j-1][i] + 1:
 // zero out run
 runs[j][i] = 0
 case cache[j-1][i-1] - runs[j-1][i-1]:
 // increase run
 runs[j][i] = runs[j-1][i-1] + 1
 case cache[j-1][i-1] + 1:
 runs[j][i] = 0
 default:
 // impossible
 break
 }
 //                        print("\(cost) ", separator: " ", terminator: "")
 }
 }
 return cache[unknown.count][command.count]
 }
 let mincost = costs.min() ?? 0
 let bestMatch = cases[costs.index(of: mincost)!]
 self = Command(rawValue: bestMatch)!
 }
 }
 }
 */
