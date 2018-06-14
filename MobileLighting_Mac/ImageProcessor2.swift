//
//  ImageProcessor2.swift
//  demo
//
//  Created by Nicholas Mosier on 6/28/17.
//  Copyright © 2017 Nicholas Mosier. All rights reserved.
//

import Foundation
import Darwin
import Yaml

func decodedImageHandler(_ decodedImPath: String, horizontal: Bool, projector: Int, position: Int) {
    let direction: Int = horizontal ? 1 : 0
    
    var received = false
    let completionHandler = { received = true }
    photoReceiver.dataReceiver = SceneMetadataReceiver(completionHandler, path: dirStruc.metadataFile(direction))
    while !received {}
    
    let outdir = dirStruc.subdir(dirStruc.refined, proj: projector, pos: position)
//    let completionHandler: () -> Void = {
        let filepath = dirStruc.metadataFile(direction)
        do {
            let metadataStr = try String(contentsOfFile: filepath)
            let metadata: Yaml = try Yaml.load(metadataStr)
            if let angle: Double = metadata.dictionary?[Yaml.string("angle")]?.double {
                refineDecodedIm(swift2Cstr(outdir), horizontal ? 1:0, swift2Cstr(decodedImPath), angle)
            } else {
                print("refine error: could not load angle (double) from YML file.")
            }
        } catch {
            print("refine error: could not load metadata file.")
        }
//    }
}

//MARK: disparity matching functions
// uses bridged C++ code from ActiveLighting image processing pipeline
// NOTE: this decoding step is not yet automated; it must manually be executed from
//    the main command-line user input loop

// computes & saves disparity maps for images of the given image position pair taken with the given projector
func disparityMatch(projector: Int, leftpos: Int, rightpos: Int) {
    let refinedDirLeft = dirStruc.subdir(dirStruc.refined, proj: projector, pos: leftpos)
    let refinedDirRight = dirStruc.subdir(dirStruc.refined, proj: projector, pos: rightpos)
    let disparityDirLeft = dirStruc.subdir(dirStruc.disparity, proj: projector, pos: leftpos)
    let disparityDirRight = dirStruc.subdir(dirStruc.disparity, proj: projector, pos: rightpos)
    let l = Int32(leftpos)
    let r = Int32(rightpos)
    disparitiesOfRefinedImgs(swift2Cstr(refinedDirLeft), swift2Cstr(refinedDirRight),
                             swift2Cstr(disparityDirLeft),
                             swift2Cstr(disparityDirRight),
                             l, r,
                             0, 0, 0, 0)
}

// computes & saves disparity maps for all positions taken for the given projector
func disparityMatch(projector: Int) {
    let dir = dirStruc.subdir(dirStruc.refined, proj: projector)//scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir+"/proj\(projector)"
    let subdirs: [String]
    do {
        subdirs = try FileManager.default.contentsOfDirectory(atPath: dir)
    } catch {
        print("disparityMatch: error enumerating subpaths of directory \(dir)")
        return
    }
    
    
    
    var positions: [Int?] = subdirs.map { subdir in
        guard let range = subdir.range(of: "pos"), subdir.hasPrefix("pos") else {
            return nil
        }
        var subdir2 = subdir
        subdir2.removeSubrange(range)
        return Int(subdir2)  // valid iff of form pos%d
    }
    positions = positions.filter { pos in
        return pos != nil
    }
    var valid: [Int] = positions.map { pos in
        return pos!
    }
    valid.sort()
    for i in 0..<valid.count-1 {
        disparityMatch(projector: projector, leftpos: valid[i], rightpos: valid[i+1])
    }
}

// computes & saves disparity maps for all adjacent positions taken from all projectors
func disparityMatch() {
    let dir = dirStruc.refined //scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir
    let subdirs: [String]
    do {
        subdirs = try FileManager.default.subpathsOfDirectory(atPath: dir)
    } catch {
        print("disparityMatch: error enumerating subpaths of directory \(dir)")
        return
    }
    
    for subdir in subdirs {
        guard let range = subdir.range(of: "proj") else {
            continue
        }
        var subdir2 = subdir
        subdir2.removeSubrange(range)
        guard let projID = Int(subdir2) else {
            continue
        }
        disparityMatch(projector: projID)
    }
}

func rectify(left: Int, right: Int, proj: Int) {
    let intr = swift2Cstr(dirStruc.intrinsicsYML)
    let extr = swift2Cstr(dirStruc.extrinsicsYML(left: left, right: right))
    let rectdirleft = dirStruc.subdir(dirStruc.rectified, proj: proj, pos: left)
    let rectdirright = dirStruc.subdir(dirStruc.rectified, proj: proj, pos: right)
    let result0l = swift2Cstr(dirStruc.decodedFile(0, proj: proj, pos: left))
    let result0r = swift2Cstr(dirStruc.decodedFile(0, proj: proj, pos: right))
    let result1l = swift2Cstr(dirStruc.decodedFile(1, proj: proj, pos: left))
    let result1r = swift2Cstr(dirStruc.decodedFile(1, proj: proj, pos: right))
    print(dirStruc.intrinsicsYML)
    print(dirStruc.extrinsicsYML(left: left, right: right))
    print(dirStruc.decodedFile(0, proj: proj, pos: left))
    computeMaps(result0l, intr, extr)
    print("HERE")
    rectifyDecoded(0, result0l, swift2Cstr(rectdirleft + "/result0-rectified.pfm"))
    rectifyDecoded(0, result1l, swift2Cstr(rectdirleft + "/result1-rectified.pfm"))
    rectifyDecoded(1, result0r, swift2Cstr(rectdirright + "/result0-rectified.pfm"))
    rectifyDecoded(1, result1r, swift2Cstr(rectdirright + "/result1-rectified.pfm"))
}
