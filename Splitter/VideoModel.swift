//
//  VideoModel.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import Foundation
import UniformTypeIdentifiers

struct FFmpegConfig: Sendable {
    let ffmpegPath: URL
    let ffprobePath: URL
    let segmentSize: Double
    let splitEnabled: Bool
    let startNumberStr: String
    let filenamePrefix: String
    let outputDirectory: URL
    let videos: [InputVideo]
}

struct InputVideo: Identifiable, Hashable, Sendable {
    let id: URL
    var hasError: Bool = false
    var name: String { id.lastPathComponent }
}

struct FFprobeOutput: nonisolated Codable, Sendable {
    struct Stream: Codable, Equatable, Sendable {
        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let sample_rate: String?
    }
    struct Format: Codable, Sendable {
        let duration: String?
    }
    
    let streams: [Stream]?
    let format: Format?
}

struct VideoCompatibilityError: LocalizedError, Sendable {
    let videoIds: Set<URL>
    var errorDescription: String? {
        NSLocalizedString("Video(s) have a different codec, resolution, or audio format than the first video", comment: "Incompatible video file")
    }
}

enum ProcessingState: Sendable {
    case idle
    case processing(Double) // 0.0 to 1.0
    case completed
    case error(String)
}
