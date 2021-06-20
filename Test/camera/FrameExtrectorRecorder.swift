//
//  FrameExtrectorRecorder.swift
//  OpenCvFaceDetection
//
//  Created by Charanbir sandhu on 15/07/20.
//  Copyright © 2020 Charan Sandhu. All rights reserved.
//

import UIKit
import AVKit

extension FrameExtractor {
    
    private func removeTemporaryVideoFileIfAny() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: temporaryVideoFileURL.path) {
            try? fileManager.removeItem(at: temporaryVideoFileURL)
        }
    }
    
    private func makeAssetWriter() -> AVAssetWriter? {
        do {
            return try AVAssetWriter(url: temporaryVideoFileURL, fileType: .mov)
        } catch {
            delegate?.recorderDidFail(error: RecorderError.couldNotCreateAssetWriter(error))
            return nil
        }
    }
    
    private func makeAssetWriterVideoInput() -> AVAssetWriterInput {
        let settings: [String: Any]
        if #available(iOS 11.0, *) {
            settings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: currentVideoDimensions?.width ?? 0,
                AVVideoHeightKey: currentVideoDimensions?.height ?? 0,
            ]
        } else {
            settings = [
                AVVideoCodecKey: AVVideoCodecH264,
                AVVideoWidthKey: currentVideoDimensions?.width ?? 0,
                AVVideoHeightKey: currentVideoDimensions?.height ?? 0,
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }
    
    // create a pixel buffer adaptor for the asset writer; we need to obtain pixel buffers for rendering later from its pixel buffer pool
    private func makeAssetWriterInputPixelBufferAdaptor(with input: AVAssetWriterInput) -> AVAssetWriterInputPixelBufferAdaptor {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: currentVideoDimensions?.width ?? 0,
            kCVPixelBufferHeightKey as String: currentVideoDimensions?.height ?? 0,
            kCVPixelFormatOpenGLESCompatibility as String: kCFBooleanTrue!,
        ]
        return AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )
    }
    
    private func makeAudioCompressionSettings() -> [String: Any]? {
        guard let currentAudioSampleBufferFormatDescription = self.currentAudioSampleBufferFormatDescription else {
            delegate?.recorderDidFail(error: RecorderError.couldNotGetAudioSampleBufferFormatDescription)
            return nil
        }

        let channelLayoutData: Data
        var layoutSize: size_t = 0
        if let channelLayout = CMAudioFormatDescriptionGetChannelLayout(currentAudioSampleBufferFormatDescription, sizeOut: &layoutSize) {
            channelLayoutData = Data(bytes: channelLayout, count: layoutSize)
        } else {
            channelLayoutData = Data()
        }

        guard let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(currentAudioSampleBufferFormatDescription) else {
            delegate?.recorderDidFail(error: RecorderError.couldNotGetStreamBasicDescriptionOfAudioSampleBuffer)
            return nil
        }

        // record the audio at AAC format, bitrate 64000, sample rate and channel number using the basic description from the audio samples
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: basicDescription.pointee.mChannelsPerFrame,
            AVSampleRateKey: basicDescription.pointee.mSampleRate,
            AVEncoderBitRateKey: 64000,
            AVChannelLayoutKey: channelLayoutData,
        ]
    }
    
    func startRecording() {
        sessionQueue.async { [unowned self] in
            self.removeTemporaryVideoFileIfAny()

            guard let newAssetWriter = self.makeAssetWriter() else { return }

            let newAssetWriterVideoInput = self.makeAssetWriterVideoInput()
            let canAddInput = newAssetWriter.canAdd(newAssetWriterVideoInput)
            if canAddInput {
                newAssetWriter.add(newAssetWriterVideoInput)
            } else {
                self.delegate?.recorderDidFail(error: RecorderError.couldNotAddAssetWriterVideoInput)
                self.assetWriterVideoInput = nil
                return
            }

            let newAssetWriterInputPixelBufferAdaptor = self.makeAssetWriterInputPixelBufferAdaptor(with: newAssetWriterVideoInput)

            guard let audioCompressionSettings = self.makeAudioCompressionSettings() else { return }
            let canApplayOutputSettings = newAssetWriter.canApply(outputSettings: audioCompressionSettings, forMediaType: .audio)
            if canApplayOutputSettings {
                let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioCompressionSettings)
                assetWriterAudioInput.expectsMediaDataInRealTime = true
                self.assetWriterAudioInput = assetWriterAudioInput

                let canAddInput = newAssetWriter.canAdd(assetWriterAudioInput)
                if canAddInput {
                    newAssetWriter.add(assetWriterAudioInput)
                } else {
                    self.delegate?.recorderDidFail(error: RecorderError.couldNotAddAssetWriterAudioInput)
                    self.assetWriterAudioInput = nil
                    return
                }
            } else {
                self.delegate?.recorderDidFail(error: RecorderError.couldNotApplyAudioOutputSettings)
                return
            }

            self.videoWritingStarted = false
            self.assetWriter = newAssetWriter
            self.assetWriterVideoInput = newAssetWriterVideoInput
            self.assetWriterInputPixelBufferAdaptor = newAssetWriterInputPixelBufferAdaptor

            self.delegate?.recorderDidStartRecording()
            self.isRecording = true
        }
    }
    
    func stopRecording() {
        isRecording = false
        guard let writer = assetWriter else { return }

        assetWriterVideoInput = nil
        assetWriterAudioInput = nil
        assetWriterInputPixelBufferAdaptor = nil
        assetWriter = nil

        delegate?.recorderWillStartWriting()

        sessionQueue.async { [unowned self] in
            writer.endSession(atSourceTime: self.currentVideoTime)
            writer.finishWriting {
                switch writer.status {
                case .failed:
                    self.delegate?.recorderDidFail(error: RecorderError.couldNotCompleteWritingVideo)
                case .completed:
                    
                    let fileName = UUID().uuidString
                    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName).appendingPathExtension("mov")
                    Composer.compose(videoURL: writer.outputURL, outputURL: tempURL) { [weak self] url in
                        guard let self = self else { return }
                        if let url = url {
                            self.delegate?.recorderDidFinishWriting(outputURL: url)
                        } else {
                            self.delegate?.recorderDidFail(error: RecorderError.couldNotCompleteWritingVideo)
                        }
                    }
                default:
                    break
                }
            }
            self.delegate?.recorderDidFinishRecording()
        }
    }
    
    func abortRecording() {
        isRecording = false
        guard let writer = assetWriter else { return }
        writer.cancelWriting()
        assetWriterVideoInput = nil
        assetWriterAudioInput = nil
        assetWriter = nil

        // remove the temp file
        let fileURL = writer.outputURL
        try? FileManager.default.removeItem(at: fileURL)

        delegate?.recorderDidAbortRecording()
    }
}
