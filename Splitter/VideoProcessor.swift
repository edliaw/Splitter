//
//  VideoProcessor.swift
//  Splitter
//
//  Created by Edward Liaw on 3/3/26.
//

import Foundation
internal import OrderedCollections

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
    
    nonisolated func runFFprobe(video: URL, ffprobePath: URL) async throws -> FFprobeOutput {
        let process = Process()
        process.executableURL = ffprobePath
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration:stream=codec_type,codec_name,width,height,sample_rate",
            "-of", "json",
            video.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        return try JSONDecoder().decode(FFprobeOutput.self, from: data)
    }

    nonisolated func batchRunFFprobe(config: FFmpegConfig) async throws -> [FFprobeOutput] {
        let maxConcurrentTasks = ProcessInfo.processInfo.activeProcessorCount
        
        return try await withThrowingTaskGroup(of: (Int, FFprobeOutput).self) { group in
            var results: [(Int, FFprobeOutput)] = []
            var activeTasks = 0
            
            for (index, video) in config.videos.enumerated() {
                if activeTasks >= maxConcurrentTasks {
                    if let result = try await group.next() {
                        results.append(result)
                    }
                    activeTasks -= 1
                }
                
                group.addTask {
                    try Task.checkCancellation()
                    let output = try await self.runFFprobe(video: video.id, ffprobePath: config.ffprobePath)
                    return (index, output)
                }
                activeTasks += 1
            }
            while activeTasks > 0 {
                if let result = try await group.next() {
                    results.append(result)
                }
                activeTasks -= 1
            }
            
            return results.sorted(by: { $0.0 < $1.0 }).map { $1 }
        }
    }
    
    nonisolated func checkCompatAndTotalDuration(config: FFmpegConfig, outputs: [FFprobeOutput]) throws -> Double {
        var total: Double = 0
        var referenceStreams: [FFprobeOutput.Stream]?
        var errors = Set<URL>()
        
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
    
    nonisolated func createConcatFile(config: FFmpegConfig) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let fileURL = tempDir.appendingPathComponent("concat_\(uuid).txt")
        
        var content = ""
        for video in config.videos {
            // FFmpeg concat file format requires escaped paths
            let safePath = video.id.path.replacingOccurrences(of: "'", with: "'\\''")
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
            "-y", // force overwrites files
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
        
        var errorLog: [String] = []
        let maxLogLines = 5
        
        try process.run()
        for try await line in pipe.fileHandleForReading.bytes.lines {
            errorLog.append(line)
            if errorLog.count >  maxLogLines {
                errorLog.removeFirst()
            }
            guard line.contains("time=") else { continue }
            let components = line.components(separatedBy: "time=")
            guard components.count > 1 else { continue }
            let timePart = components[1].components(separatedBy: " ")[0]
            guard let currentSeconds = timeStringToSeconds(timePart) else { continue }
            let progress = min(currentSeconds / totalDuration, 1.0)
            // Safely report progress back to the caller
            await onProgress(progress)
        }
        process.waitUntilExit()
        
        self.activeProcess = nil
        
        try? FileManager.default.removeItem(at: listURL)
        
        try Task.checkCancellation()
        if process.terminationStatus != 0 {
            let logString = errorLog.joined(separator: "\n")
            let errorMessage = "FFmpeg failed with \(process.terminationStatus)\nLog:\n\(logString)"
            throw NSError(domain: "FFmpegError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
}
