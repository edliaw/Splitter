//
//  VideoModel.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import Foundation
import UniformTypeIdentifiers

struct InputVideo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var hasError: Bool = false
    var name: String { url.lastPathComponent }
}

struct FFprobeOutput: Codable {
    struct Stream: Codable, Equatable {
        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let sample_rate: String?
    }
    struct Format: Codable {
        let duration: String?
    }
    
    let streams: [Stream]?
    let format: Format?
}

enum ProcessingState {
    case idle
    case processing(Double) // 0.0 to 1.0
    case completed
    case error(String)
}

// Helper to convert HH:MM:SS.ms to seconds
func timeStringToSeconds(_ timeString: String) -> Double? {
    let components = timeString.components(separatedBy: ":")
    guard components.count >= 3 else { return nil }
    
    let hours = Double(components[0]) ?? 0
    let minutes = Double(components[1]) ?? 0
    let seconds = Double(components[2]) ?? 0
    
    return (hours * 3600) + (minutes * 60) + seconds
}
