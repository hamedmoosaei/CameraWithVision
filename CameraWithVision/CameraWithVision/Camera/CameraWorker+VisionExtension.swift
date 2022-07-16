//
//  CameraWorker+VisionExtension.swift
//  Farashenasa
//
//  Created by Hamed on 12/7/21.
//

import AVFoundation
import Vision

// MARK: Vision
extension CameraWorker {
    
    func prepareBuffersForFaceDetection(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        let detectFaceRequest = VNDetectFaceLandmarksRequest(completionHandler: faceDetection)
        do {
            try sequenceHandler.perform(
                [detectFaceRequest],
                on: imageBuffer,
                orientation: .up)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    private func faceDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNFaceObservation]  else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.visionError = .noFault
            
            var _ = self.check(results: results, self.faceCount)?
                .check(result: results[0], self.facePosition)
                .check(result: results[0], self.faceDistance)
                .check(result: results[0], self.faceOrientation)
                .check(result: results[0], self.faceAngle)
            
            self.delegate?.cameraFaceState(cameraState: self.visionError)
        }
    }
    
    private func check(results: [VNFaceObservation], _ callback: ([VNFaceObservation]) -> FaceStateType) -> CameraWorker? {
        if results.count == 0 {
            self.visionError = .notFound
            return nil
        }
        if self.visionError == .noFault {
            self.visionError = callback(results)
        }
        return self
    }
    
    private func check(result: VNFaceObservation, _ callback: (VNFaceObservation) -> FaceStateType) -> CameraWorker {
        if self.visionError == .noFault {
            self.visionError = callback(result)
        }
        return self
    }

    private func faceCount(results: [VNFaceObservation]) -> FaceStateType {
        if results.count == 0 {
            return .notFound
        } else if results.count > 1 {
            return .multiple
        }
        return .noFault
    }

    private func facePosition(result: VNFaceObservation) -> FaceStateType {
        guard let legalRect = faceLegalBound else { return .noFault }
        guard let cameraView = cameraView else { return .noFault }

        let normalizeboundingBoxMinX = result.boundingBox.minX * cameraView.frame.size.width
        let normalizeboundingBoxMaxX = result.boundingBox.maxX * cameraView.frame.size.width
        let normalizeboundingBoxMinY = (1 - result.boundingBox.minY) * cameraView.frame.size.height
        let normalizeboundingBoxMaxY = (1 - result.boundingBox.maxY) * cameraView.frame.size.height

        let minXValidation = (legalRect.minX...legalRect.maxX).contains(normalizeboundingBoxMinX)
        let maxXValidation = (legalRect.minX...legalRect.maxX).contains(normalizeboundingBoxMaxX)
        let minYValidation = (legalRect.minY...legalRect.maxY).contains(normalizeboundingBoxMinY)
        let maxYValidation = (legalRect.minY...legalRect.maxY).contains(normalizeboundingBoxMaxY)

        if !minXValidation || !maxXValidation || !minYValidation || !maxYValidation {
            return .notInPosition
        }
        return .noFault
    }

    private func faceDistance(result: VNFaceObservation) -> FaceStateType {
        if result.boundingBox.size.height > 0.4 {
            return .tooClose
        } else if result.boundingBox.size.height < 0.2 {
            return .tooFar
        }
        return .noFault
    }

    private func faceOrientation(result: VNFaceObservation) -> FaceStateType {
        if #available(iOS 12.0, *),
           let roll = result.roll?.doubleValue,
           roll < -0.5 || roll > 0.5 {
            return .wrongOrientation
        }
        return .noFault
    }

    private func faceAngle(result: VNFaceObservation) -> FaceStateType {
        if #available(iOS 12.0, *),
           let yaw = result.yaw?.doubleValue {
            if yaw < -0.75 {
                return .tooLeft
            } else if yaw > 0.75 {
                return .tooRight
            }
        }
        return .noFault
    }
}
