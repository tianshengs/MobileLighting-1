//
//  FullscreenWindowView.swift
//  demo_mac
//
//  Created by Nicholas Mosier on 6/1/17.
//  Copyright © 2017 Nicholas Mosier. All rights reserved.
//

import Cocoa
import Foundation
import CoreGraphics

class FullscreenWindow: NSView {
    enum DisplayContent {
        case None
        case Image
        case BinaryCode
        case Checkerboard(Int)  // can store square size
        case White, Black
    }
    
    var fullscreenWindow: NSWindow!
    var screen: NSScreen!
    var displayContent: DisplayContent = .None
    var image: CGImage?
    
    var codeDrawer: BinaryCodeDrawer?
    var currentCodeBit: Int?
    var currentSystem: BinaryCodeSystem?
    
    init(on screen: NSScreen) {
        super.init(frame: screen.frame)
        
        let contentRect = NSMakeRect(screen.frame.minX, screen.frame.minY, screen.frame.maxX-screen.frame.minX, screen.frame.maxY-screen.frame.minY)
        let window = NSWindow(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = self
        window.isOpaque = true
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        window.orderFront(nil)
        
        self.fullscreenWindow = window
        self.screen = screen
        self.codeDrawer = BinaryCodeDrawer(context: self.fullscreenWindow.graphicsContext!, frame: screen.frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // make sure correct graphics context has been set
        NSGraphicsContext.setCurrent(self.fullscreenWindow.graphicsContext)
        guard let graphicsContext = NSGraphicsContext.current() else {
            Swift.print("Cannot draw fullscreen window content: current graphics context is nil.")
            return
        }
        
        let context: CGContext = graphicsContext.cgContext
        
        switch displayContent {
        case .None:
            break
            
        case .Image:
            if let image = image {
                context.draw(image, in: self.frame)
            }
            break
        
        case .BinaryCode:
            if let codeDrawer = codeDrawer, let currentCodeBit = currentCodeBit, let currentSystem = currentSystem {
                codeDrawer.drawCode(forBit: currentCodeBit, system: currentSystem, positionLimit: (currentSystem == BinaryCodeSystem.MinStripeWidthCode) ? 1024 : nil)
            }
            break
            
        case .Checkerboard(let squareSize):            
            let width = Int(screen.frame.width), height = Int(screen.frame.height)
            let bitmapPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: width*height)
            defer {
                bitmapPtr.deallocate(capacity: width*height)
            }
            
            let whitePix: UInt32 = 0xFFFFFFFF, blackPix: UInt32 = UInt32(0xFF000000)
            for row in 0..<height {
                let rowPtr = bitmapPtr.advanced(by: row*width)
                for col in 0..<width {
                    (rowPtr+col).pointee = ( ((col/squareSize) % 2) == ((row/squareSize) % 2) ) ? blackPix : whitePix
                }
            }
            let provider = CGDataProvider(data: NSData(bytes: bitmapPtr, length: width*height*4))
            let colorspace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
            let info: CGBitmapInfo = [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
            let image = CGImage(width: width, height: height,
                                bitsPerComponent: 8, bitsPerPixel: 4*8, bytesPerRow: 4*width, space: colorspace, bitmapInfo: info, provider: provider!,
                                decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
            context.draw(image!, in: CGRect(x: 0, y: 0, width: width, height: height))
            break
            
        case .White:
            break
            
        case .Black:
            break
        }
        
        /*
        if let image = image {
            context.draw(image, in: self.frame)
        } else if let codeDrawer = codeDrawer, let currentCodeBit = currentCodeBit, let currentSystem = currentSystem {
            codeDrawer.drawCode(forBit: currentCodeBit, system: currentSystem, positionLimit: (currentSystem == BinaryCodeSystem.MinStripeWidthCode) ? 1024 : nil)
        } */
    }
    
    func drawImage(_ image: CGImage) {
        self.displayContent = .Image
        self.image = image
        NSGraphicsContext.setCurrent(self.fullscreenWindow.graphicsContext)
        let context = self.fullscreenWindow.graphicsContext!.cgContext
        context.draw(image, in: self.frame)
        self.setNeedsDisplay(self.frame)
    }
    
    func configureDisplaySettings(horizontal: Bool = false, inverted: Bool = false) {
        guard let codeDrawer = codeDrawer else {
            Swift.print("FullscreenWindow: cannot configure display settings — binary code drawer not yet configured.")
            return
        }
        
        (codeDrawer.drawHorizontally, codeDrawer.drawInverted) = (horizontal, inverted)
    }
    
    func displayBinaryCode(forBit bit: Int, system: BinaryCodeSystem) {
        NSGraphicsContext.setCurrent(self.fullscreenWindow.graphicsContext)
        
        currentCodeBit = bit
        currentSystem = system
        
        self.displayContent = .BinaryCode
        self.display()
    }
    
    func displayCheckerboard(squareSize: Int = 2) {
        self.displayContent = .Checkerboard(squareSize)
        self.display()
    }
}
