//
//  VideoModel.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import Foundation
import UniformTypeIdentifiers

// Configuration parameters for app
nonisolated struct VideoProcessorConfig: Sendable {
    let segmentSize: Double
    let splitEnabled: Bool
    let startNumberStr: String
    let filenamePrefix: String
    let outputDirectory: URL
    let videos: [InputVideo]
}

// Video model
nonisolated struct InputVideo: Identifiable, Hashable, Sendable {
    let id: URL
    var hasError: Bool = false
    var name: String { id.lastPathComponent }
    
    static func == (lhs: InputVideo, rhs: InputVideo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// FFprobe output JSON structure
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

// Error for mismatched video properties
struct VideoCompatibilityError: LocalizedError, Sendable {
    let videoIds: Set<URL>
    var errorDescription: String? {
        NSLocalizedString("Video(s) have a different codec, resolution, or audio format than the first video", comment: "Incompatible video file")
    }
}

// Application's processing state
enum ProcessingState: Sendable {
    case idle
    case processing(Double) // 0.0 to 1.0
    case completed
    case error(String)
}
