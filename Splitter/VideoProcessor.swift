//
//  VideoProcessor.swift
//  Splitter
//
//  Created by Edward Liaw on 3/3/26.
//

import Foundation

// Helper to convert HH:MM:SS.ms to seconds
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

actor VideoProcessor {
    private var activeProcess: Process?
    
    func cancel() {
        activeProcess?.terminate()
        activeProcess = nil
    }

    func runFFprobe(config: FFmpegConfig) async throws -> [FFprobeOutput] {
        return try await withThrowingTaskGroup(of: (Int, FFprobeOutput).self) { group in
            for (index, video) in config.videos.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    let process = Process()
                    process.executableURL = config.ffprobePath
                    process.arguments = [
                        "-v", "error",
                        "-show_entries", "format=duration:stream=codec_type,codec_name,width,height,sample_rate",
                        "-of", "json",
                        video.url.path
                    ]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    
                    try process.run()
                    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
                    process.waitUntilExit()
                    
                    let output = try JSONDecoder().decode(FFprobeOutput.self, from: data)
                    
                    return (index, output)
                }
            }
            var results: [(Int, FFprobeOutput)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted(by: { $0.0 < $1.0 }).map { $1 }
        }
    }
    
    func checkCompatAndTotalDuration(config: FFmpegConfig, outputs: [FFprobeOutput]) throws -> Double {
        var total: Double = 0
        var referenceStreams: [FFprobeOutput.Stream]?
        var errors = Set<UUID>()
        
        for (index, output) in outputs.enumerated() {
            if let durationStr = output.format?.duration, let duration = Double(durationStr) {
                total += duration
            } else {
                errors.insert(config.videos[index].id)
                continue
            }
            guard let allStreams = output.streams else {
                errors.insert(config.videos[index].id)
                continue
            }
            let relevantStreams = allStreams.filter { $0.codec_type == "video" || $0.codec_type == "audio" }
            if referenceStreams == nil {
                // Set the first video as the baseline
                referenceStreams = relevantStreams
            } else if referenceStreams != relevantStreams {
                errors.insert(config.videos[index].id)
            }
        }
        if !errors.isEmpty {
            throw VideoCompatibilityError(videoIds: errors)
        }
        return total
    }
    
    func createConcatFile(config: FFmpegConfig) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let fileURL = tempDir.appendingPathComponent("concat_\(uuid).txt")
        
        var content = ""
        for video in config.videos {
            // FFmpeg concat file format requires escaped paths
            let safePath = video.url.path.replacingOccurrences(of: "'", with: "'\\''")
            content += "file '\(safePath)'\n"
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func runFFmpeg(config: FFmpegConfig, listURL: URL, totalDuration: Double, onProgress: @Sendable @escaping (Double) async -> Void) async throws {
        let process = Process()
        self.activeProcess = process
        process.executableURL = config.ffmpegPath
        
        var filename = config.filenamePrefix
        if config.splitEnabled {
            filename += "%03d.mp4"
        } else {
            filename += ".mp4"
        }
        
        let outputPattern = config.outputDirectory.appendingPathComponent(filename).path
        let segmentTime = config.segmentSize * 60
                
        // Command: Concat inputs -> Split into 10 min (600s) segments
        // Note: We use -c copy for speed (no re-encoding). If input codecs differ, this may fail.
        // To fix that, remove "-c copy" to force re-encoding (slower).
        var args = [
            "-f", "concat",
            "-safe", "0",
            "-i", listURL.path,
            "-c", "copy",
            "-ignore_unknown",
            "-map", "0"
        ]
        if config.splitEnabled {
            args += [
                "-f", "segment",
                "-segment_time", "\(segmentTime)",
                "-reset_timestamps", "1",
            ]
            if config.startNumberStr != "000" {
                args += [
                    "-segment_start_number", config.startNumberStr,
                ]
            }
        }
        args.append(outputPattern)
        
        process.arguments = args
        
        let pipe = Pipe()
        process.standardError = pipe // FFmpeg writes progress to stderr
        
        try process.run()
        for try await line in pipe.fileHandleForReading.bytes.lines {
            if line.contains("time=") {
                let components = line.components(separatedBy: "time=")
                if components.count > 1 {
                    let timePart = components[1].components(separatedBy: " ")[0]
                    if let currentSeconds = timeStringToSeconds(timePart) {
                        let progress = min(currentSeconds / totalDuration, 1.0)
                        
                        // Safely report progress back to the caller
                        await onProgress(progress)
                    }
                }
            }
        }
        
        self.activeProcess = nil
        
        try? FileManager.default.removeItem(at: listURL)
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "FFmpegError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg failed"])
        }
    }
}
