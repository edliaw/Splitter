//
//  SplitterHelpers.swift
//  Splitter
//
//  Created by Edward Liaw on 3/4/26.
//

import SwiftUI
import Foundation
internal import OrderedCollections

// Reorders elements in OrderedSet
extension OrderedSet {
    mutating func move(fromOffsets indices: IndexSet, toOffset destination: Int) {
        let elements: [Element] = indices.map { self.elements[$0] }
        self.elements.remove(atOffsets: indices)
        let correctedDestination = destination - indices.count(in: 0..<destination)
        self.elements.insert(contentsOf: elements, at: correctedDestination)
    }
}

// Set up process environment with additional system paths
nonisolated func createEnvProcess() -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    
    var env = ProcessInfo.processInfo.environment
    let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
    process.environment = env
    
    return process
}

// Converts ffmpeg time format HH:MM:SS.ms to seconds
nonisolated func timeStringToSeconds(_ timeString: String) -> Double? {
    let components = timeString.components(separatedBy: ":").compactMap { Double($0) }
    var totalSeconds: Double = 0
    var multiplier: Double = 1
    
    for value in components.reversed() {
        totalSeconds += value * multiplier
        multiplier *= 60
    }
    
    return totalSeconds > 0 ? totalSeconds : nil
}

// Generates the output filename
nonisolated func buildFilename(filenamePrefix: String, splitEnabled: Bool, startNumberStr: String = "%03d") -> String {
    if splitEnabled {
        return "\(filenamePrefix)\(startNumberStr).mp4"
    } else {
        return "\(filenamePrefix).mp4"
    }
}
