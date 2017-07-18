//
//  ImageProcessor2.swift
//  demo
//
//  Created by Nicholas Mosier on 6/28/17.
//  Copyright © 2017 Nicholas Mosier. All rights reserved.
//

import Foundation

func decodedImageHandler(_ decodedImPath: String, horizontal: Bool, projector: Int, position: Int) {
    let outdir = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir+"/proj\(projector)/pos\(position)"
    do {
        try FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true, attributes: nil)
    } catch {
        return
    }
    refineDecodedIm(swift2Cstr(outdir), horizontal ? 1:0, swift2Cstr(decodedImPath))
}

//MARK: disparity matching functions

// computes & saves disparity maps for images of the given image position pair taken with the given projector
func disparityMatch(projector: Int, leftpos: Int, rightpos: Int) {
    let refinedDirLeft = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir+"/proj\(projector)/pos\(leftpos)"
    let refinedDirRight = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir+"/proj\(projector)/pos\(rightpos)"
    let disparityDirLeft = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+disparitySubdir+"/proj\(projector)"
    let disparityDirRight = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+disparitySubdir+"/proj\(projector)"
    let disparityFileLeft = "disp\(leftpos)\(rightpos).flo"
    let disparityFileRight = "disp\(rightpos)\(leftpos).flo"
    let fileman = FileManager.default
    do {
        try fileman.createDirectory(atPath: disparityDirLeft, withIntermediateDirectories: true, attributes: nil)
        try fileman.createDirectory(atPath: disparityDirRight, withIntermediateDirectories: true, attributes: nil)
    } catch {
        print("ImageProcessor2: could not create directory at either:\n\t\(disparityDirLeft)\n\t\(disparityDirRight)")
        return
    }
    //disparitiesOfRefinedImgs(swift2Cstr(refinedDirLeft), swift2Cstr(refinedDirRight))
    disparitiesOfRefinedImgs(swift2Cstr(refinedDirLeft), swift2Cstr(refinedDirRight),
                             swift2Cstr(disparityDirLeft+"/"+disparityFileLeft),
                             swift2Cstr(disparityDirRight+"/"+disparityFileRight),
                             0, 0, 0, 0)
}

// computes & saves disparity maps for all positions taken for the given projector
func disparityMatch(projector: Int) {
    let dir = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir+"/proj\(projector)"
    let fileman = FileManager.default
    let subdirs: [String]
    do {
        subdirs = try fileman.contentsOfDirectory(atPath: dir)
    } catch {
        print("disparityMatch: error enumerating subpaths of directory \(dir)")
        return
    }
    let validDirs = subdirs.filter { subdir in
        return subdir.hasPrefix("pos")
    }
    for pos in 0..<validDirs.count-1 {    // 'posX'
        disparityMatch(projector: projector, leftpos: pos, rightpos: pos+1)
    }
}

// computes & saves disparity maps for all adjacent positions taken from all projectors
func disparityMatch() {
    let dir = scenesDirectory+"/"+sceneName+"/"+computedSubdir+"/"+refinedSubdir
    let fileman = FileManager.default
    let subdirs: [String]
    do {
        subdirs = try fileman.subpathsOfDirectory(atPath: dir)
    } catch {
        print("disparityMatch: error enumerating subpaths of directory \(dir)")
        return
    }
    
    for subdir in subdirs {
        guard subdir.hasPrefix("proj") else { continue }
        var subdir2 = subdir
        subdir2.removeSubrange(subdir2.range(of: "proj")!)
        guard let projID = Int(subdir2) else {
            continue
        }
        disparityMatch(projector: projID)
    }
}