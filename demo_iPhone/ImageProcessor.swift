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

func combineIntensityBuffers(_ buffers: [CVPixelBuffer]) -> CVPixelBuffer {
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
    
    var resultImage = CIImage()
    for i in 1..<inputImages.count {
        extremeIntensitiesFilter.setValue(inputImages[i], forKey: kCIInputBackgroundImageKey)
        resultImage = extremeIntensitiesFilter.outputImage!
    }
    
    context.render(resultImage, to: buffers[0])
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