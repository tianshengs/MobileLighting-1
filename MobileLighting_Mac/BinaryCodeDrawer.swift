//
// BinaryCodesDrawer.swift
// MobileLighting_Mac
//
// Contains the BinaryCodeDrawer class, which is used to display horizontal and vertical stripes
//  for structured lighting based on binary codes from BinaryCodes.swift.
//

import Foundation
import Cocoa
import CoreGraphics

let monitorTimeDelay: DispatchTimeInterval = .milliseconds(30)

struct Pixel {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}
let blackPixel = Pixel(r: 0, g: 0, b: 0, a: 255)
let whitePixel = Pixel(r: 255, g: 255, b: 255, a: 255)

class BinaryCodeDrawer {    
    let frame: CGRect
    let width: Int
    let height: Int
    var drawHorizontally: Bool = false
    var drawInverted: Bool = false
    
    var bitmaps: [CGImage] = [CGImage]()
    var bitmaps_inverted: [CGImage] = [CGImage]()
    //var bitmap: Array<Pixel>
    var bitmap: UnsafeMutablePointer<UInt8>
    
    let blackHorizontalBar: Array<Pixel>
    let whiteHorizontalBar: Array<Pixel>
    init(frame: CGRect) {
        self.frame = frame
        self.width = Int(frame.width)
        self.height = Int(frame.height)
        
        bitmap = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(width*height*4))
        blackHorizontalBar = Array<Pixel>(repeating: blackPixel, count: Int(width))
        whiteHorizontalBar = Array<Pixel>(repeating: whitePixel, count: Int(width))
    }
    
    func drawCode(forBit bit: Int, system: BinaryCodeSystem, horizontally: Bool? = nil, inverted: Bool? = nil, positionLimit: Int? = nil) {
        guard let graphicsContext = NSGraphicsContext.current else {
            Swift.print("Cannot draw fullscreen window content: current graphics context is nil.")
            return
        }
        let context = graphicsContext.cgContext
        let horizontally = horizontally ?? self.drawHorizontally
        let inverted = inverted ?? self.drawInverted       // temporarily use this configuration; does not change instance's settings
        
        var nPositions = horizontally ? height: width   // nPositions = # of diff. gray codes
        if positionLimit != nil && nPositions > positionLimit! {
            nPositions = positionLimit!
        }
        
        let bitArray: [Bool]
        switch system {
        case .GrayCode:
            bitArray = grayCodeArray(forBit: bit, size: nPositions)
            break
        case .MinStripeWidthCode:
            if minSWcodeBitDisplayArrays == nil {
                do {
                    try loadMinStripeWidthCodesForDisplay(filepath: minSWfilepath) // Try populating minSWcodeBitDisplayArrays with array of bit arrays
                } catch {
                    print("BinaryCodeDrawer: unable to load min strip width codes from data file.")
                    return
                }
            }
            guard Int(bit) < minSWcodeBitDisplayArrays!.count else {
                print("BinaryCodeDrawer: ERROR — specified bit for code too large.")
                return
            }
            
            let fullBitArray = minSWcodeBitDisplayArrays![bit] // Array of bits representing min stripe width code
            
            bitArray = Array<Bool>(fullBitArray.prefix(Int(horizontally ? height : width)))
            guard nPositions <= bitArray.count else {
                print("BinaryCodeDrawer: ERROR — cannot display min stripe width code, number of stripes too large.")
                return
            }
            break
        }
        
        var horizontalBar: Array<Pixel> = (inverted ? whiteHorizontalBar : blackHorizontalBar)
        let max: Int
        
        if !horizontally { // Display vertical bars
            max = nPositions
            var barVal: Bool
            
            for index in 0..<max {
                barVal = bitArray[index]
                horizontalBar[index] = (barVal == inverted) ? blackPixel : whitePixel
            }
            
            let data = Data(bytes: &horizontalBar, count: width*4)
            for row in 0..<height {
                data.copyBytes(to: bitmap.advanced(by: row*width*4), count: width*4)
            }
        } else { // Display horizontal bars
            max = width
            
            for row in 0..<height {
                let bar = (row < Int(nPositions)) ? ((bitArray[row] == inverted) ? blackHorizontalBar : whiteHorizontalBar) : (inverted ? whiteHorizontalBar : blackHorizontalBar)
                let data = Data(bytes: bar, count: width*4)
                data.copyBytes(to: bitmap.advanced(by: row*width*4), count: width*4)
            }
        }
 
        let provider = CGDataProvider(data: NSData(bytes: bitmap, length: width*height*4))
        let colorspace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        let info: CGBitmapInfo = [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
        let image = CGImage(width: width, height: height,
                            bitsPerComponent: 8, bitsPerPixel: 4*8, bytesPerRow: 4*width, space: colorspace, bitmapInfo: info, provider: provider!,
                            decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
        
        context.draw(image!, in: CGRect(x: 0, y: 0, width: width, height: height))        
    }
    
    
}
