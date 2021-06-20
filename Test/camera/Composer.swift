//
//  Composer.swift
//  FilterCam
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import AVKit
import Foundation

struct Composer {
    static func compose(videoURL: URL, outputURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: videoURL)

        let composition = AVMutableComposition()
        composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)

        guard let clipVideoTrack = asset.tracks(withMediaType: .video).first else {
            completion(nil)
            return
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: clipVideoTrack.naturalSize.width,
                                             height: clipVideoTrack.naturalSize.height)
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)

        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
        let t1 = CGAffineTransform(translationX: 0, y: 0)
        let t2 = t1.rotated(by: (0 * CGFloat.pi) / 180)

        let finalTransform = t2
        transformer.setTransform(finalTransform, at: CMTime.zero)
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            completion(nil)
            return
        }
        exporter.videoComposition = videoComposition
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        exporter.exportAsynchronously {
            switch exporter.status {
            case .completed:
                completion(exporter.outputURL)
            default:
                debugPrint(exporter.error)
                completion(nil)
            }
        }
    }
    
    static func composeAudioWithVideo(videoURL: URL, audioURL: URL, outputURL: URL, completion: @escaping (URL?) -> Void) {
        let mixComposition = AVMutableComposition()
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        
        let assetVideo = AVURLAsset(url: videoURL)
        let assertAudio = AVURLAsset(url: audioURL)

        let compositionAddVideo = mixComposition.addMutableTrack(withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid)
        let compositionAddAudio = mixComposition.addMutableTrack(withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid)
        
        guard let aVideoAssetTrack: AVAssetTrack = assetVideo.tracks(withMediaType: .video).first else {return}
        guard let aAudioAssetTrack: AVAssetTrack = assertAudio.tracks(withMediaType: .audio).first else {return}

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: aVideoAssetTrack.naturalSize.width,
                                             height: aVideoAssetTrack.naturalSize.height)
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: assetVideo.duration)

        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: aVideoAssetTrack)
        let t1 = CGAffineTransform(translationX: 0, y: 0)
        let t2 = t1.rotated(by: (0 * CGFloat.pi) / 180)

        let finalTransform = t2
        transformer.setTransform(finalTransform, at: CMTime.zero)
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        compositionAddVideo?.preferredTransform = aVideoAssetTrack.preferredTransform
        
        guard let compositionAddVid = compositionAddVideo else {return}
            mutableCompositionVideoTrack.append(compositionAddVid)
        guard let compositionAddAud = compositionAddAudio else {return}
            mutableCompositionAudioTrack.append(compositionAddAud)
        

        do {
            try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aVideoAssetTrack,
                                                                at: CMTime.zero)

            //In my case my audio file is longer then video file so i took videoAsset duration
            //instead of audioAsset duration
            try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aAudioAssetTrack,
                                                                at: CMTime.zero)

            
        } catch {
            print(error.localizedDescription)
        }

        guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetMediumQuality) else {
            completion(nil)
            return
        }
        exporter.videoComposition = videoComposition
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        exporter.exportAsynchronously {
            switch exporter.status {
            case .completed:
                completion(exporter.outputURL)
            default:
                debugPrint(exporter.error)
                completion(nil)
            }
        }
    }
}
