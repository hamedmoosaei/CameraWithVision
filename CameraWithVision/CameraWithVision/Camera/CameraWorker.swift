//
//  CameraWorker.swift
//  Farashenasa
//
//  Created by aliebrahimi on 11/25/21.
//

import UIKit
import Vision
import AVFoundation

protocol FaceCameraWorkerDelegate: AnyObject {
    func cameraFaceState(cameraState: FaceStateType)
}

protocol CameraPublicApi {
    // MARK: Variable
    var delegate: FaceCameraWorkerDelegate? { get set }
    var currentCameraPosition: CameraPosition { get set }
    
    // MARK: Function
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void)
    func stopCaptureSession()
    func startCaptureSession()
    func setup(isAudioEnable: Bool, handler: @escaping (Error?) -> Void )
    func displayPreview(_ view: UIView) throws
    func getVideoPermission(completion: @escaping (_ granted: Bool) -> Void)
    func getAudioPermission(completion: @escaping (_ granted: Bool) -> Void)
    func setFaceLegalBound(rect: CGRect)
    func startRecording()
    func stopRecording()
}

class CameraWorker: NSObject {
    // MARK: Variable
    weak var delegate: FaceCameraWorkerDelegate?
        
    private var captureSession: AVCaptureSession?
    private var frontCamera: AVCaptureDevice?
    private var rearCamera: AVCaptureDevice?
    private var audioDevice: AVCaptureDevice?
    
    var currentCameraPosition: CameraPosition = .front
    private var frontCameraInput: AVCaptureDeviceInput?
    private var rearCameraInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    
    private var audioInput: AVCaptureDeviceInput?
    
    let videoDataOutput = AVCaptureVideoDataOutput()
    let audioDataOutput = AVCaptureAudioDataOutput()
    
    weak var cameraView: UIView?
    var faceLegalBound: CGRect?
    
    lazy var isRecording = false
    var videoWriter: AVAssetWriter!
    var videoWriterInput: AVAssetWriterInput!
    var audioWriterInput: AVAssetWriterInput!
    var sessionAtSourceTime: CMTime?
    
    var outputFileLocation: URL!
    
    var sequenceHandler = VNSequenceRequestHandler()
    var visionError: FaceStateType = .noFault
    // MARK: Function
    private func createCaptureSession() {
        self.captureSession = AVCaptureSession()
    }
    
    private func configureCaptureDevices() throws {
        let session = AVCaptureDevice.DiscoverySession.init(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: AVMediaType.video,
            position: AVCaptureDevice.Position.unspecified)
        
        let cameras = (session.devices.compactMap { $0 })
        
        for camera in cameras {
            if camera.position == .front {
                self.frontCamera = camera
            }
            if camera.position == .back {
                self.rearCamera = camera
                
                try camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
        }
    }
    
    private func configureAudioDevice() {
        self.audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
        getAudioPermission { _ in }
    }
    
    private func configureDeviceInputs() throws {
        guard let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }
        
        if let rearCamera = self.rearCamera, self.currentCameraPosition == .rear {
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                self.currentCameraPosition = .rear
            } else {
                throw CameraControllerError.inputsAreInvalid
            }
        } else if let frontCamera = self.frontCamera, self.currentCameraPosition == .front {
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                self.currentCameraPosition = .front
            } else {
                throw CameraControllerError.inputsAreInvalid
            }
        } else {
            throw CameraControllerError.noCamerasAvailable
        }
        
        if let audioDevice = self.audioDevice {
            self.audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(self.audioInput!) {
                captureSession.addInput(self.audioInput!)
            } else {
                throw CameraControllerError.inputsAreInvalid
            }
        }
    }
    
    private func configurePhotoOutput() throws {
        guard let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }
        
        self.photoOutput = AVCapturePhotoOutput()
        if #available(iOS 11.0, *) {
            self.photoOutput?.setPreparedPhotoSettingsArray(
                [AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg ])],
                completionHandler: nil)
        }
        if captureSession.canAddOutput(self.photoOutput!) {
            captureSession.addOutput(self.photoOutput!)
        }
        self.getCameraFrames()
        captureSession.startRunning()
    }
    
    private func getCameraFrames() {
        self.videoDataOutput.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as NSString): NSNumber(value: kCVPixelFormatType_32BGRA)] as [String: Any]
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.audioDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession?.addOutput(self.videoDataOutput)
        self.captureSession?.addOutput(self.audioDataOutput)
        guard let connection = self.videoDataOutput.connection(with: AVMediaType.video),
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = .portrait
    }
    
    private func switchCameras() throws {
        guard let captureSession = self.captureSession, captureSession.isRunning
        else { throw CameraControllerError.captureSessionIsMissing }
        captureSession.beginConfiguration()
        let inputs = captureSession.inputs
        switch currentCameraPosition {
        case .front:
            try switchToRearCamera(inputs: inputs)
        case .rear:
            try switchToFrontCamera(inputs: inputs)
        }
        captureSession.commitConfiguration()
    }
    
    private func switchToFrontCamera(inputs: [AVCaptureInput]) throws {
        guard let captureSession = self.captureSession,
              let rearCameraInput = self.rearCameraInput,
              inputs.contains(rearCameraInput),
              let frontCamera = self.frontCamera
        else { throw CameraControllerError.invalidOperation }
        captureSession.removeInput(rearCameraInput)
        self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
        if captureSession.canAddInput(self.frontCameraInput!) {
            captureSession.addInput(self.frontCameraInput!)
            self.currentCameraPosition = .front
        } else { throw CameraControllerError.invalidOperation }
    }
    
    private func switchToRearCamera(inputs: [AVCaptureInput]) throws {
        guard let captureSession = self.captureSession,
              let frontCameraInput = self.frontCameraInput,
              inputs.contains(frontCameraInput),
              let rearCamera = self.rearCamera
        else { throw CameraControllerError.invalidOperation }
        captureSession.removeInput(frontCameraInput)
        self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
        if captureSession.canAddInput(rearCameraInput!) {
            captureSession.addInput(rearCameraInput!)
            self.currentCameraPosition = .rear
        } else { throw CameraControllerError.invalidOperation }
    }
    
    private func saveToGallery() {
        UISaveVideoAtPathToSavedPhotosAlbum(outputFileLocation.path, self, #selector(self.video(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func video(_ video: String, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {}
}

// MARK: CameraPublicApi
extension CameraWorker: CameraPublicApi {
    // MARK: captureImage
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }
        let settings = AVCapturePhotoSettings()
        let previewPixelType = settings.__availablePreviewPhotoPixelFormatTypes.first!
        let previewFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPixelType,
                             kCVPixelBufferWidthKey as String: 160,
                             kCVPixelBufferHeightKey as String: 160
        ]
        settings.previewPhotoFormat = previewFormat
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
    
    // MARK: stopRunning
    func stopCaptureSession() {
        self.captureSession?.stopRunning()
    }
    
    // MARK: startRunning
    func startCaptureSession() {
        self.captureSession?.startRunning()
    }
    
    // MARK: Start recording
    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        sessionAtSourceTime = nil
        setupWriter()
    }

    // MARK: Stop recording
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioWriterInput.markAsFinished()
        videoWriterInput.markAsFinished()
        videoWriter.finishWriting { [weak self] in
            self?.sessionAtSourceTime = nil
        }
        self.stopCaptureSession()
    }
    
    // MARK: setup
    func setup(isAudioEnable: Bool, handler: @escaping (Error?) -> Void ) {
        DispatchQueue(label: "setup").async {
            do {
                self.createCaptureSession()
                try self.configureCaptureDevices()
                if isAudioEnable {
                    self.configureAudioDevice()
                }
                try self.configureDeviceInputs()
                try self.configurePhotoOutput()
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
                return
            }
            DispatchQueue.main.async {
                handler(nil)
            }
        }
    }
    
    // MARK: displayPreview
    func displayPreview(_ view: UIView) throws {
        self.cameraView = view
        guard let captureSession = self.captureSession, captureSession.isRunning
        else {
            throw CameraControllerError.captureSessionIsMissing
        }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height)
    }
    
    // MARK: getVideoPermission
    func getVideoPermission(completion: @escaping (_ granted: Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
    
    // MARK: getAudioPermission
    func getAudioPermission(completion: @escaping (_ granted: Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
    
    func setFaceLegalBound(rect: CGRect) {
        self.faceLegalBound = rect
    }
}

// MARK: AVCapturePhotoCaptureDelegate
extension CameraWorker: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { self.photoCaptureCompletionBlock?(nil, error) }
        if let data = photo.fileDataRepresentation() {
            let image = UIImage(data: data)
            self.photoCaptureCompletionBlock?(image, nil)
        } else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
}

// MARK: SampleBufferDelegate
extension CameraWorker: AVCaptureVideoDataOutputSampleBufferDelegate,
                        AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        prepareBuffersForAssetWriter(output: output, sampleBuffer: sampleBuffer, connection: connection)
        prepareBuffersForFaceDetection(sampleBuffer: sampleBuffer)
    }
}

// MARK: CameraControllerError
enum CameraControllerError: Swift.Error {
    case captureSessionAlreadyRunning
    case captureSessionIsMissing
    case inputsAreInvalid
    case invalidOperation
    case noCamerasAvailable
    case unknown
}
enum CameraPosition {
    case front
    case rear
}
