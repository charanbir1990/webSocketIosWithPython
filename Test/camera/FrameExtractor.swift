//
//  FrameExtractor.swift
//  OpenCvFaceDetection
//
//  Created by Charanbir sandhu on 15/07/20.
//  Copyright © 2020 Charan Sandhu. All rights reserved.
//

import UIKit
import AVKit

protocol FrameExtractorDelegate: class {
    func recorderCanSetFilter(image: CIImage) -> CIImage
    func recorderDidUpdate(image: UIImage)
    func recorderDidStartRecording()
    func recorderDidAbortRecording()
    func recorderDidFinishRecording()
    func recorderWillStartWriting()
    func recorderDidFinishWriting(outputURL: URL)
    func recorderDidFail(error: Error & LocalizedError)
}

class FrameExtractor: NSObject {
    var temporaryVideoFileURL: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("recording")
            .appendingPathExtension("mov")
    }
    var videoWritingStarted = false
    var videoWritingStartTime = CMTime()
    var assetWriter: AVAssetWriter?
    var assetWriterAudioInput: AVAssetWriterInput?
    var assetWriterVideoInput: AVAssetWriterInput?
    var assetWriterInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var currentAudioSampleBufferFormatDescription: CMFormatDescription?
    var currentVideoDimensions: CMVideoDimensions?
    var currentVideoTime = CMTime()
    
    private var position = AVCaptureDevice.Position.back
    private let quality = AVCaptureSession.Preset.hd1280x720
    
    private var permissionGranted = false
    let sessionQueue = DispatchQueue(label: "session queue")
    let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var audioDeviceInput: AVCaptureDeviceInput?
    let context = CIContext()
    private var zoom: CGFloat = 1
    private var beginZoomScale: CGFloat = 1
    private var hasFlash: Bool {
        return videoDevice?.hasTorch ?? false
    }
    var isRecording = false
    var torchLevel: Float = 0 {
        didSet {
            if !hasFlash { return }
            if !(videoDevice?.isTorchAvailable ?? false) { return }
            try? videoDevice?.lockForConfiguration()
            if torchLevel > 0.1 {
                try? videoDevice?.setTorchModeOn(level: torchLevel)
            } else {
                videoDevice?.torchMode = .off
            }
            videoDevice?.unlockForConfiguration()
        }
    }
    
    weak var delegate: FrameExtractorDelegate?
    
    override init() {
        super.init()
        checkPermission()
        sessionQueue.async { [unowned self] in
            self.configureSession()
            self.captureSession.startRunning()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    @objc private func applicationDidEnterBackground(_: Notification) {
        if isRecording {
            stopRecording()
        }
    }
    
    @objc private func sessionWasInterrupted(notification: NSNotification) {
        if isRecording {
            stopRecording()
        }
        sessionQueue.async {
            if let audioDeviceInput = self.audioDeviceInput {
                self.captureSession.removeInput(audioDeviceInput)
            }
        }
    }
    
    @objc private func sessionInterruptionEnded(notification: NSNotification) {
        
    }
    
    public func flipCamera() {
        sessionQueue.async { [unowned self] in
            self.captureSession.beginConfiguration()
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }
            self.position = self.position == .front ? .back : .front
            self.configureSession()
            self.captureSession.commitConfiguration()
        }
    }
    
    // MARK: AVSession configuration
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            requestPermission()
        default:
            permissionGranted = false
        }
    }
    
    private func requestPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { [unowned self] granted in
            self.permissionGranted = granted
            self.sessionQueue.resume()
        }
    }
    
    private func configureSession() {
        guard permissionGranted else { return }
        captureSession.sessionPreset = quality
        
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: position) {
            self.videoDevice = videoDevice
            if let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) {
                if captureSession.canAddInput(videoDeviceInput) {
                    captureSession.addInput(videoDeviceInput)
                }
            }
        }
        
        if let audioDevice = getAudioDevice(){
            if let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice) {
                self.audioDeviceInput = audioDeviceInput
                if captureSession.canAddInput(audioDeviceInput) {
                    captureSession.addInput(audioDeviceInput)
                }
            }
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer video"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        let audiooutput = AVCaptureAudioDataOutput()
        audiooutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer audio"))
        if captureSession.canAddOutput(audiooutput) {
            captureSession.addOutput(audiooutput)
        }
        
        guard let connection = videoOutput.connection(with: AVFoundation.AVMediaType.video) else { return }
        guard connection.isVideoOrientationSupported else { return }
        guard connection.isVideoMirroringSupported else { return }
        connection.videoOrientation = .portrait
        connection.isVideoMirrored = position == .front
        
    }
    
    private func getAudioDevice() ->AVCaptureDevice? {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowAirPlay, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("Failed to set background audio preference")
        }
        let audioDevice = AVCaptureDevice.default(.builtInMicrophone, for: .audio, position: .unspecified)
        return audioDevice
    }
    
    func pinch(gestureRecognizer: UIPinchGestureRecognizer) {
        guard let videoDevice = videoDevice else {return}
        if gestureRecognizer.state == .began {
            beginZoomScale = zoom
        }
        var device: AVCaptureDevice = videoDevice
        var error:NSError!
        do{
            try device.lockForConfiguration()
            defer {device.unlockForConfiguration()}
            zoom = min(3, max(1.0, min(beginZoomScale * gestureRecognizer.scale,  device.activeFormat.videoMaxZoomFactor)))
            device.videoZoomFactor = zoom
        }catch{}
    }
    
    func focus(at point: CGPoint) {
        guard let videoDevice = videoDevice else {return}
        do {
            try videoDevice.lockForConfiguration()
            if videoDevice.isFocusPointOfInterestSupported == true {
                videoDevice.focusPointOfInterest = point
                videoDevice.focusMode = .autoFocus
            }
            videoDevice.exposurePointOfInterest = point
            videoDevice.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
            videoDevice.unlockForConfiguration()
        } catch {
            // just ignore
        }
    }
}

