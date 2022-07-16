//
//  CameraWorker+AssetWriter.swift
//  Farashenasa
//
//  Created by Hamed on 12/12/21.
//

import AVFoundation
import UIKit

extension CameraWorker {
    
    func prepareBuffersForAssetWriter(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) {
        let writable = canWrite()
        
        if writable, sessionAtSourceTime == nil {
            sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            videoWriter.startSession(atSourceTime: sessionAtSourceTime!)
        }
        
        if output == videoDataOutput {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        if writable,
           output == videoDataOutput,
           (videoWriterInput.isReadyForMoreMediaData) {
            videoWriterInput.append(sampleBuffer)
        } else if writable,
                  output == audioDataOutput,
                  (audioWriterInput.isReadyForMoreMediaData) {
            audioWriterInput?.append(sampleBuffer)
        }
    }
    
    func setupWriter() {
        do {
            outputFileLocation = videoFileLocation()
            videoWriter = try AVAssetWriter(url: outputFileLocation, fileType: AVFileType.mp4)
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video,
                                                  outputSettings: [
                                                    AVVideoCodecKey: AVVideoCodecType.h264,
                                                    AVVideoWidthKey: 720,
                                                    AVVideoHeightKey: 1280,
                                                    AVVideoCompressionPropertiesKey: [
                                                        AVVideoAverageBitRateKey: 2300000
                                                    ]
                                                  ])
            videoWriterInput.expectsMediaDataInRealTime = true
            if videoWriter.canAdd(videoWriterInput) {
                videoWriter.add(videoWriterInput)
            }
            
            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio,
                                                  outputSettings: [
                                                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                    AVNumberOfChannelsKey: 1,
                                                    AVSampleRateKey: 44100,
                                                    AVEncoderBitRateKey: 64000
                                                  ])
            audioWriterInput.expectsMediaDataInRealTime = true
            if videoWriter.canAdd(audioWriterInput) {
                videoWriter.add(audioWriterInput)
            }
            
            videoWriter.startWriting()
            
        } catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    private func canWrite() -> Bool {
        return isRecording
        && videoWriter != nil
        && videoWriter.status == .writing
    }
    
    private func videoFileLocation() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let videoOutputUrl = documentsPath[0].appendingPathComponent("videoFile.mp4")
        do {
            if FileManager.default.fileExists(atPath: videoOutputUrl.path) {
                try FileManager.default.removeItem(at: videoOutputUrl)
                print("file removed")
            }
        } catch {
            print(error)
        }
        
        return videoOutputUrl
    }
}
