//
//  FaceStateErrors.swift
//  CameraWithVision
//
//  Created by Hamed on 7/16/22.
//

import Foundation

enum FaceStateType {
    case notFound
    case multiple
    case notInPosition
    case tooFar
    case tooClose
    case wrongOrientation
    case noFault
    case tooLeft
    case tooRight
    
    var errorText: String {
        switch self {
        case .notFound:
            return "Face not Found"
        case .multiple:
            return "Multipe Faces"
        case .notInPosition:
            return "Face is Out of the box"
        case .tooFar:
            return "Face is too far"
        case .tooClose:
            return "Face is to close"
        case .wrongOrientation:
            return "Wrong orientation"
        case .tooLeft:
            return "Face is turned to left"
        case .tooRight:
            return "Face is turned to right"
        case .noFault:
            return ""
        }
    }
}
