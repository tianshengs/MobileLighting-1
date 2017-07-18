//
//  ImageProcessor.swift
//  demo
//
//  Created by Nicholas Mosier on 6/9/17.
//  Copyright © 2017 Nicholas Mosier. All rights reserved.
//

import Foundation
import AVFoundation
import CoreImage

// used by custom threshold filter as default when no input threshold specified
var thresholdDefault: Float = 0.06
var binaryCodeDirection: Bool?

let context = CIContext(options: [kCIContextWorkingColorSpace : NSNull()])

func processPixelBufferPair(normal: CVPixelBuffer, inverted: CVPixelBuffer) -> CVPixelBuffer {
    // test intensity difference filter
    let imageN = CIImage(cvPixelBuffer: normal)
    let imageI = CIImage(cvPixelBuffer: inverted)
    let filter = IntensityDifferenceFilter()
    filter.setValue(imageN, forKey: kCIInputImageKey)
    filter.setValue(imageI, forKey: kCIInputBackgroundImageKey)
    let imageDiff = filter.outputImage!
    
    let grayscaleFilter = GrayscaleFilter()
    grayscaleFilter.setValue(imageDiff, forKey: kCIInputImageKey)
    grayscaleFilter.setValue([1.0/3, 1.0/3, 1.0/3] as [Float], forKey: GrayscaleFilter.kCIRGBWeightsKey)
    let imageGray = grayscaleFilter.outputImage!
    context.render(imageGray, to: normal)
    
    return normal
    
}

func processPixelBufferPair_builtInFilters(normal: CVPixelBuffer, inverted: CVPixelBuffer) -> CVPixelBuffer {
    let lockFlags = CVPixelBufferLockFlags(rawValue: 0) // read & write
    CVPixelBufferLockBaseAddress(normal, lockFlags)
    CVPixelBufferLockBaseAddress(inverted, lockFlags)
    
    var imNormal: CIImage = CIImage(cvPixelBuffer: normal)
    var imInverted: CIImage = CIImage(cvPixelBuffer: inverted)
    
    // apply gray monochrome filter to colors
    let colorMonochromeFilter = CIFilter(name: "CIColorMonochrome")!
    colorMonochromeFilter.setValue(CIColor.gray(), forKey: kCIInputColorKey)
    
    colorMonochromeFilter.setValue(imNormal, forKey: kCIInputImageKey)
    imNormal = colorMonochromeFilter.outputImage!
    colorMonochromeFilter.setValue(imInverted, forKey: kCIInputImageKey)
    imInverted = colorMonochromeFilter.outputImage!
    
    // invert colors for image of inverted pattern
    let colorInvertFilter = CIFilter(name: "CIColorInvert")!
    colorInvertFilter.setValue(imInverted, forKey: kCIInputImageKey)
    imInverted = colorInvertFilter.outputImage!
    
    // scale exposures by 0.5
    let exposureAdjustFilter = CIFilter(name: "CIExposureAdjust")!
    exposureAdjustFilter.setValue(-1.0, forKey: kCIInputEVKey)
    exposureAdjustFilter.setValue(imNormal, forKey: kCIInputImageKey)
    imNormal = exposureAdjustFilter.outputImage!
    
    exposureAdjustFilter.setValue(imInverted, forKey: kCIInputImageKey)
    imInverted = exposureAdjustFilter.outputImage!
    
    // add imNormal and imInverted together
    let additionCompositingFilter = CIFilter(name: "CIAdditionCompositing")!
    additionCompositingFilter.setValue(imNormal, forKey: kCIInputImageKey)
    additionCompositingFilter.setValue(imInverted, forKey: kCIInputBackgroundImageKey)
    
    let resultingImage = additionCompositingFilter.outputImage!
    context.render(resultingImage, to: normal)
    return normal
}

func processPixelBufferPair_withPixelLoop(normal: CVPixelBuffer, inverted: CVPixelBuffer) -> CVPixelBuffer {
    print("Image Processor: width of buffer \(CVPixelBufferGetWidth(normal)), height of buffer \(CVPixelBufferGetHeight(normal))")
    
    print("ImageProcessor: processing pixel buffer pair")
    
    let lockFlags = CVPixelBufferLockFlags(rawValue: 0) // read & write
    CVPixelBufferLockBaseAddress(normal, lockFlags)
    CVPixelBufferLockBaseAddress(inverted, lockFlags)
    
    guard normal.width == inverted.width, normal.height == inverted.height, normal.bytesPerRow == inverted.bytesPerRow, normal.pixelFormatType == inverted.pixelFormatType else {
        print("ImageProcessor: error – pixel buffers not of same type.")
        return normal
    }
    
    let rowCount = normal.height
    let colCount = normal.width
    let bytesPerRow = normal.bytesPerRow
    
    print("ImageProcessor: bytes per row \(bytesPerRow), cols \(colCount)")
    
    for row in 0..<rowCount {
        let offset = bytesPerRow * row
        let rowPtr_normal = normal.baseAddress!.advanced(by: offset)
        let rowPtr_inverted = inverted.baseAddress!.advanced(by: offset)
        
        let rowData_normal = Data(bytes: rowPtr_normal, count: bytesPerRow)
        let rowData_inverted = Data(bytes: rowPtr_inverted, count: bytesPerRow)
        var rowData_intensity = Data(repeating: 255, count: bytesPerRow)
        
        for col in 0..<colCount {
            var intensityDiff: Int
            intensityDiff = ((Int(rowData_normal[col*4]) + Int(rowData_normal[col*4+1]) + Int(rowData_normal[col*4+2])) -
                Int(rowData_inverted[col*4]) - Int(rowData_inverted[col*4+1]) - Int(rowData_inverted[col*4+2])) / 3
            var value: UInt8
            intensityDiff += 128
            intensityDiff = (intensityDiff > 255) ? 255 : intensityDiff
            intensityDiff = (intensityDiff < 0) ? 0 : intensityDiff
            value = UInt8(intensityDiff)
            
            rowData_intensity[col*4] = value
            rowData_intensity[col*4+1] = value
            rowData_intensity[col*4+2] = value
            rowData_intensity[col*4+3] = 255    // A
        }
        let temp_nsData = rowData_intensity as NSData
        rowPtr_normal.copyBytes(from: temp_nsData.bytes, count: bytesPerRow)
        
    }
    
    CVPixelBufferUnlockBaseAddress(normal, lockFlags)
    CVPixelBufferUnlockBaseAddress(inverted, lockFlags)
    
    return normal
}

//////////////////////////
//TEMP
var prethreshPGM: PGMFile?
//////////////////////////

func combineIntensityBuffers(_ buffers: [CVPixelBuffer], shouldThreshold: Bool) -> CVPixelBuffer {
    guard buffers.count > 0 else {
        fatalError("ImageProcessor: fatal error — number of buffers supplied must be >= 1.")
    }
    
    if buffers.count == 1 {
        return buffers[0]
    }
    
    var inputImages: [CIImage] = buffers.map { (buffer: CVPixelBuffer) -> CIImage in
        return CIImage(cvPixelBuffer: buffer)
    }
    
    let extremeIntensitiesFilter = ExtremeIntensitiesFilter()
    extremeIntensitiesFilter.setValue(inputImages[0], forKey: kCIInputImageKey)
    
    var resultImage: CIImage = CIImage()
    for i in 1..<inputImages.count {
        extremeIntensitiesFilter.setValue(inputImages[i], forKey: kCIInputBackgroundImageKey)
        resultImage = extremeIntensitiesFilter.outputImage!
    }
    
    
    /*
    // TEMP
    var thresh2: CVPixelBuffer? = nil
    CVPixelBufferCreate(nil, buffers[0].width, buffers[0].height, kCVPixelFormatType_32BGRA, nil, &thresh2)
    thresholdDefault = 0.03; let thresholdFilter2 = ThresholdFilter2()
    thresholdFilter2.setValue(resultImage, forKey: kCIInputImageKey)
    let thresheldImage2 = thresholdFilter2.outputImage!
    context.render(thresheldImage2, to: thresh2!)
    */
    
    ///////////////////////////////////
    // TEMP: for sending pre-threshold combined intensity buffer
    var prethresh: CVPixelBuffer? = nil
    CVPixelBufferCreate(nil, buffers[0].width, buffers[0].height, kCVPixelFormatType_32BGRA, nil, &prethresh)
    context.render(resultImage, to: prethresh!)
    prethreshPGM = PGMFile(buffer: prethresh!)
    ///////////////////////////////////
    
    
    if (shouldThreshold) {
        //thresholdDefault = 0.03; let thresholdFilter = ThresholdFilter()
        thresholdDefault = 0.03; let thresholdFilter = ThresholdFilter2()
        thresholdFilter.setValue(resultImage, forKey: kCIInputImageKey)
        thresholdFilter.setValue(CGFloat(0.035), forKey: "inputThreshold")
        thresholdFilter.setValue(CGFloat(-Double.pi/4.0), forKey: "inputAngle")
        
        //thresholdFilter.setValue(resultImage, forKey: kCIInputImageKey)
        let thresheldImage = thresholdFilter.outputImage!
        context.render(thresheldImage, to: buffers[0])
    } else {
        context.render(resultImage, to: buffers[0])
    }
    
    
    /*
    // compare buffers
    let lockFlags = CVPixelBufferLockFlags(rawValue: 0) // read & write
    CVPixelBufferLockBaseAddress(buffers[0], lockFlags)
    CVPixelBufferLockBaseAddress(thresh2!, lockFlags)
    
    var thresh1Ptr = CVPixelBufferGetBaseAddress(buffers[0])!.bindMemory(to: UInt8.self, capacity: buffers[0].width*buffers[0].height*4)
    var thresh2Ptr = CVPixelBufferGetBaseAddress(thresh2!)!.bindMemory(to: UInt8.self, capacity: buffers[0].width*buffers[0].height*4)
    for i in 0..<thresh2!.width*thresh2!.height {
        var val1 = thresh1Ptr.pointee
        var val2 = thresh2Ptr.pointee
        if (val1 == 128 || val1 == 127) && !(val2 == 128 || val2 == 127) {
            thresh1Ptr.pointee = 0; thresh1Ptr.advanced(by: 1).pointee = 255; thresh1Ptr.advanced(by: 2).pointee = 0
        } else if !(val1 == 128 || val1 == 127) && (val2 == 128 || val2 == 127) {
            thresh1Ptr.pointee = 0; thresh1Ptr.advanced(by: 1).pointee = 0; thresh1Ptr.advanced(by: 2).pointee = 255
        }
        thresh1Ptr = thresh1Ptr.advanced(by: 4)
        thresh2Ptr = thresh2Ptr.advanced(by: 4)
    }
    
    CVPixelBufferUnlockBaseAddress(buffers[0], lockFlags)
    CVPixelBufferUnlockBaseAddress(thresh2!, lockFlags)
 */
    
    return buffers[0]
}

extension CVPixelBuffer {
    var baseAddress: UnsafeMutableRawPointer? {
        get {
            return CVPixelBufferGetBaseAddress(self)
        }
    }
    var width: Int {
        get {
            return CVPixelBufferGetWidth(self)
        }
    }
    
    var height: Int {
        get {
            return CVPixelBufferGetHeight(self)
        }
    }
    var pixelFormatType: OSType {
        get {
            return CVPixelBufferGetPixelFormatType(self)
        }
    }
    var bytesPerRow: Int {
        get {
            return CVPixelBufferGetBytesPerRow(self)
        }
    }
    
    func deepcopy() -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let format = CVPixelBufferGetPixelFormatType(self)
        var pixelBufferCopyOptional:CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, format, nil, &pixelBufferCopyOptional)
        if let pixelBufferCopy = pixelBufferCopyOptional {
            CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0x00000001)) // kCVPixelBufferLock_ReadOnly
            CVPixelBufferLockBaseAddress(pixelBufferCopy, CVPixelBufferLockFlags(rawValue: 0))
            let baseAddress = CVPixelBufferGetBaseAddress(self)
            let dataSize = CVPixelBufferGetDataSize(self)
            print("dataSize: \(dataSize)")
            let target = CVPixelBufferGetBaseAddress(pixelBufferCopy)
            memcpy(target, baseAddress, dataSize)
            CVPixelBufferUnlockBaseAddress(pixelBufferCopy, CVPixelBufferLockFlags(rawValue: 0))
            CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0x00000001))
        }
        return pixelBufferCopyOptional
    }
}

//MARK: Decoder class
class Decoder {
    // properties
    let binaryCodeSystem: BinaryCodeSystem
    var valueArray: [UInt32] // use Int32 so masking works properly
    var unknownArray: [UInt32]
    let width: Int
    let height: Int
    
    init(width: Int, height: Int, binaryCodeSystem: BinaryCodeSystem) {
        self.width = width
        self.height = height
        self.valueArray = Array<UInt32>(repeating: 0, count: width*height)
        self.unknownArray = Array<UInt32>(repeating: 0, count: width*height)
        
        self.binaryCodeSystem = binaryCodeSystem
        
        if binaryCodeSystem == .MinStripeWidthCode && minSW_codeToPos == nil {
            do {
                let filepath = Bundle.main.resourcePath! + "/minSW.dat" 
                try loadMinSWCodesConversionArrays(filepath: filepath)
            } catch {
                print("Decoder: failed to load minSWcodes for processing.")
            }
        }
    }
    
    func decodeThreshold(_ thresholdBuffer: CVPixelBuffer, forBit bit: Int) {
        guard width == thresholdBuffer.width &&
            height == thresholdBuffer.height else {
                print("ImageProcessor Decoder: ERROR — mismatch in dimensions of provided threshold image with existing decoder pixel array.")
                return
        }
        
        CVPixelBufferLockBaseAddress(thresholdBuffer, CVPixelBufferLockFlags(rawValue: 0))
        var threshPtr = CVPixelBufferGetBaseAddress(thresholdBuffer)!.bindMemory(to: UInt8.self, capacity: width*height*4)
        
        for i in 0..<width*height {
            let threshval = threshPtr.pointee
            if threshval == 128 {
                unknownArray[i] |= UInt32(1 << bit)
            } else if threshval == 255 {
                valueArray[i] |= UInt32(1 << bit)
            } else if threshval != 0 {
                print ("ImageProcessor — WARNING, VALUE \(threshval) UNEXPECTED")
            }
            
            threshPtr = threshPtr.advanced(by: 4)
        }
        
        CVPixelBufferUnlockBaseAddress(thresholdBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
    }
    
    // ROTATED
    func getPFMData() -> Data {
        let pfmHeaderStr: NSString = "Pf\n\(height) \(width)\n-1\n" as NSString
        var pfmData = pfmHeaderStr.data(using: String.Encoding.utf8.rawValue)!
        
        let arrlen: Int = width*height
        let arrlenm1: Int = arrlen-1    // for optimization in rotation calculation
        var pfmBodyArray: [Float] = Array<Float>(repeating: 0.0, count: arrlen)
        for i in 0..<width*height {
            let val: Float
            if (unknownArray[i] == 0) {
                let code = valueArray[i]
                
                switch binaryCodeSystem {
                case .GrayCode:
                    let pos = decodeGrayCode(of: code)
                    val = Float(exactly: pos)!
                case .MinStripeWidthCode:
                    if code < UInt32(minSW_codeToPos!.count) {  // make sure codeToPos function defined for code
                        let pos = minSW_codeToPos![Int(code)]
                        val = Float(exactly: pos)!
                    } else {
                        val = Float.infinity
                    }
                }
            } else {
                val = Float.infinity
            }
            // rotates i
            // optimized way of calculating this?
            //let x_rot = height - i/width - 1
            //let y_rot = width - i%width - 1
            //let i_rot = y_rot*height + x_rot
            let i_rot = arrlenm1 - height*(i%width) - i/width   // optimized version of calculation above
            pfmBodyArray[i_rot] = val
        }
        
        let pfmBodyData = Data(bytes: &pfmBodyArray, count: width*height*MemoryLayout<Float>.size)
        pfmData.append(pfmBodyData)
        
        return pfmData
    }
    
    
}


class PGMFile {
    var buffer: CVPixelBuffer
    var imageWidth: Int
    var imageHeight: Int
    
    let maxGray: UInt8 = 255
    let bufferLockFlags = CVPixelBufferLockFlags(rawValue: 0)
    var rotate: Bool
    
    private var header: NSString {
        get {
            if rotate {
                return "P5 \(imageHeight) \(imageWidth) \(maxGray)\n" as NSString
            } else {
                return "P5 \(imageWidth) \(imageHeight) \(maxGray)\n" as NSString
            }
        }
    }
    
    init(buffer: CVPixelBuffer, rotate: Bool = true) {
        self.buffer = buffer
        self.imageWidth = buffer.width
        self.imageHeight = buffer.height
        self.rotate = rotate
    }
    
    func getPGMData() -> Data {
        var data: Data = self.header.data(using: String.Encoding.utf8.rawValue)!
        
        CVPixelBufferLockBaseAddress(buffer, bufferLockFlags)
        
        let ptr = buffer.baseAddress!.bindMemory(to: UInt8.self, capacity: imageWidth*imageHeight*4)
        
        let arrlenm1 = imageHeight*imageWidth - 1
        var body: [UInt8] = Array<UInt8>(repeating: 0, count: imageWidth*imageHeight)
        for i in 0..<imageWidth*imageHeight {
            let value = ptr.advanced(by: i*4).pointee
            if rotate {
                let i_rot = imageHeight*(i%imageWidth) + i/imageWidth   // rotates index so image upright
                body[i_rot] = value
            } else {
                body[i] = value
            }
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, bufferLockFlags)
        
        data.append(&body, count: imageWidth*imageHeight)
        return data
    }
}