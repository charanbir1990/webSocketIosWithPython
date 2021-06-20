//
//  FrameExtrectorDelegates.swift
//  OpenCvFaceDetection
//
//  Created by Charanbir sandhu on 15/07/20.
//  Copyright © 2020 Charan Sandhu. All rights reserved.
//

import UIKit
import AVKit

extension FrameExtractor: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        if mediaType == kCMMediaType_Audio {
            handleAudioSampleBuffer(buffer: sampleBuffer)
        } else if mediaType == kCMMediaType_Video {
            handleVideoSampleBuffer(buffer: sampleBuffer)
        }
    }
    
    private func handleAudioSampleBuffer(buffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(buffer) else { return }
        currentAudioSampleBufferFormatDescription = formatDesc

        // write the audio data if it's from the audio connection
        if assetWriter == nil { return }
        guard let input = assetWriterAudioInput else { return }
        if input.isReadyForMoreMediaData {
            let success = input.append(buffer)
            if !success {
                delegate?.recorderDidFail(error: RecorderError.couldNotWriteAudioData)
                abortRecording()
            }
        }
    }
    
    private func handleVideoSampleBuffer(buffer: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        // update the video dimensions information
        guard let formatDesc = CMSampleBufferGetFormatDescription(buffer) else { return }
        currentVideoDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)

        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let sourceImage = CIImage(cvPixelBuffer: imageBuffer)

        // run the filter through the filter chain
        guard let filteredImage = self.delegate?.recorderCanSetFilter(image: sourceImage) else { return }

        guard let writer = assetWriter, let pixelBufferAdaptor = assetWriterInputPixelBufferAdaptor else {
            getUIImageFromCIImage(ciImage: filteredImage)
            return
        }

        // if we need to write video and haven't started yet, start writing
        if !videoWritingStarted {
            videoWritingStarted = true
            let success = writer.startWriting()
            if !success {
                delegate?.recorderDidFail(error: RecorderError.couldNotWriteVideoData)
                abortRecording()
                return
            }

            writer.startSession(atSourceTime: timestamp)
            videoWritingStartTime = timestamp
        }

        guard let renderedOutputPixelBuffer = getRenderedOutputPixcelBuffer(adaptor: pixelBufferAdaptor) else { return }
        
        CIContext().render(filteredImage, to: renderedOutputPixelBuffer)
        
        // pass option nil to enable color matching at the output, otherwise the color will be off
        let drawImage = CIImage(cvPixelBuffer: renderedOutputPixelBuffer)
        getUIImageFromCIImage(ciImage: drawImage)

        currentVideoTime = timestamp

        // write the video data
        guard let input = assetWriterVideoInput else { return }
        if input.isReadyForMoreMediaData {
            let success = pixelBufferAdaptor.append(renderedOutputPixelBuffer, withPresentationTime: timestamp)
            if !success {
                delegate?.recorderDidFail(error: RecorderError.couldNotWriteVideoData)
            }
        }
    }
    
    private func getRenderedOutputPixcelBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor?) -> CVPixelBuffer? {
        guard let pixelBufferPool = adaptor?.pixelBufferPool else {
            NSLog("Cannot get pixel buffer pool")
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard let renderedOutputPixelBuffer = pixelBuffer else {
            NSLog("Cannot obtain a pixel buffer from the buffer pool")
            return nil
        }

        return renderedOutputPixelBuffer
    }
    
    // MARK: CIImage to UIImage conversion
    func getUIImageFromCIImage(ciImage: CIImage) {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        delegate?.recorderDidUpdate(image: uiImage)
    }
}
