//
//  AppViewModel.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
class AppViewModel: ObservableObject {
    @Published var videos: [InputVideo] = []
    @Published var outputDirectory: URL?
    @Published var filenamePrefix: String = "segment"
    @Published var state: ProcessingState = .idle
    @Published var progressDescription: String = ""
    @Published var showingAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showMissingFFmpegAlert = false
    
    var ffmpegPath = ""
    var ffprobePath = ""
    
    // MARK: - File Management
    func addFiles(urls: [URL]) {
        for url in urls {
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false {
                if !videos.contains(where: { $0.url == url }) {
                    videos.append(InputVideo(url: url))
                }
            }
        }
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        videos.move(fromOffsets: source, toOffset: destination)
    }
    
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            self.outputDirectory = panel.url
        }
    }
    
    // MARK: - FFmpeg Logic
    func startProcessing() {
        if let foundPath = findFFmpeg() {
            self.ffmpegPath = foundPath
            self.ffprobePath = foundPath.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
        } else {
            self.showingAlert = true
            self.alertTitle = "FFmpeg Not Found"
            self.alertMessage = "This app requires FFmpeg to function.\n\nPlease install it via Homebrew by running:\n'brew install ffmpeg'\nin your Terminal."
            return
        }
        
        guard !videos.isEmpty else {
            self.showingAlert = true
            self.alertTitle = "Video Files Missing"
            self.alertMessage = "Please add video files first."
            return
        }
        
        guard let outputDir = outputDirectory else {
            self.showingAlert = true
            self.alertTitle = "Output Directory Required"
            self.alertMessage = "Please select an output directory."
            return
        }

        state = .processing(0.0)
        progressDescription = "Calculating total duration..."
        
        Task.detached {
            do {
                // 1. Calculate Total Duration
                let totalDuration = try await self.calculateTotalDuration()
                
                // 2. Create Concat List File
                let listURL = try await self.createConcatFile()
                
                // 3. Run FFmpeg
                try await self.runFFmpeg(listURL: listURL, outputDir: outputDir, totalDuration: totalDuration)
                
                await MainActor.run {
                    self.state = .completed
                    self.progressDescription = "Done!"
                }
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }
    
    private func findFFmpeg() -> String? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private func calculateTotalDuration() async throws -> Double {
        var total: Double = 0
        
        for video in videos {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobePath)
            process.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", video.url.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), let duration = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                total += duration
            }
        }
        return total
    }
    
    private func createConcatFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("concat_list.txt")
        
        var content = ""
        for video in videos {
            // FFmpeg concat file format requires escaped paths
            let safePath = video.url.path.replacingOccurrences(of: "'", with: "'\\''")
            content += "file '\(safePath)'\n"
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func runFFmpeg(listURL: URL, outputDir: URL, totalDuration: Double) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        let outputPattern = outputDir.appendingPathComponent("\(filenamePrefix)_%03d.mp4").path
        
        // Command: Concat inputs -> Split into 10 min (600s) segments
        // Note: We use -c copy for speed (no re-encoding). If input codecs differ, this may fail.
        // To fix that, remove "-c copy" to force re-encoding (slower).
        process.arguments = [
            "-f", "concat",
            "-safe", "0",
            "-i", listURL.path,
            "-c", "copy",
            "-map", "0",
            "-f", "segment",
            "-segment_time", "600", // 10 minutes
            "-reset_timestamps", "1",
            outputPattern
        ]
        
        let pipe = Pipe()
        process.standardError = pipe // FFmpeg writes progress to stderr
        
        process.terminationHandler = { _ in }
        
        try process.run()
        
        // Read progress line by line
        let handle = pipe.fileHandleForReading
        for try await line in handle.bytes.lines {
            // Parse "time=00:01:23.45"
            if line.contains("time=") {
                let components = line.components(separatedBy: "time=")
                if components.count > 1 {
                    let timePart = components[1].components(separatedBy: " ")[0]
                    if let currentSeconds = timeStringToSeconds(timePart) {
                        let progress = min(currentSeconds / totalDuration, 1.0)
                        
                        await MainActor.run {
                            self.state = .processing(progress)
                            self.progressDescription = "Processing: \(Int(progress * 100))%"
                        }
                    }
                }
            }
        }
        
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "FFmpegError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg failed"])
        }
    }
}
