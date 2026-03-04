//
//  AppViewModel.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
internal import OrderedCollections

extension OrderedSet {
    mutating func move(fromOffsets indices: IndexSet, toOffset destination: Int) {
        let elements: [Element] = indices.map { self.elements[$0] }
        self.elements.remove(atOffsets: indices)
        let correctedDestination = destination - indices.count(in: 0..<destination)
        self.elements.insert(contentsOf: elements, at: correctedDestination)
    }
}

@MainActor
class AppViewModel: ObservableObject {
    @Published var videos: OrderedSet<InputVideo> = OrderedSet()
    @Published var state: ProcessingState = .idle
    @Published var progressDescription: String = ""
    @Published var showingAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    var ffmpegPath: URL?
    var ffprobePath: URL?

    private let processor = VideoProcessor()
    private var processingTask: Task<Void, Never>?
    
    // MARK: - File Management
    func addFiles(urls: [URL]) {
        for url in urls {
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .mpeg4Movie) ?? false {
                videos.append(InputVideo(id: url))
            }
        }
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        videos.move(fromOffsets: source, toOffset: destination)
    }
    
    func deleteItem(video: InputVideo) {
        withAnimation {
            if let index = videos.firstIndex(of: video) {
                videos.remove(at: index)
            }
        }
    }

    func selectOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    private func findFFmpeg() -> Bool {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                self.ffmpegPath = URL(fileURLWithPath: path)
                self.ffprobePath = URL(fileURLWithPath: path.replacingOccurrences(of: "ffmpeg", with: "ffprobe"))
                return true
            }
        }
        return false
    }
    
    // MARK: - Process the video
    func startProcessing(outputDirectory: URL?, filenamePrefix: String, startNumberStr: String, segmentSize: Double, splitEnabled: Bool) {
        guard findFFmpeg() else {
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
        
        self.videos = OrderedSet(self.videos.map { video in
            var updatedVideo = video
            updatedVideo.hasError = false
            return updatedVideo
        })

        let config = FFmpegConfig(
            ffmpegPath: self.ffmpegPath!,
            ffprobePath: self.ffprobePath!,
            segmentSize: segmentSize,
            splitEnabled: splitEnabled,
            startNumberStr: startNumberStr,
            filenamePrefix: filenamePrefix,
            outputDirectory: outputDir,
            videos: Array(self.videos)
        )

        state = .processing(0.0)
        progressDescription = "Calculating total duration..."
        
        // MARK: - Start task
        processingTask = Task {
            do {
                // 1. Analyze videos with ffprobe
                let outputs = try await self.processor.runFFprobe(config: config)
                let totalDuration = try await self.processor.checkCompatAndTotalDuration(config: config, outputs: outputs)
                
                // 2. Create Concat List File
                let listURL = try await self.processor.createConcatFile(config: config)
                
                // 3. Run FFmpeg
                try await self.processor.runFFmpeg(config: config, listURL: listURL, totalDuration: totalDuration) { progress in
                    await MainActor.run {
                        self.state = .processing(progress)
                        self.progressDescription = "Processing: \(Int(progress * 100))%"
                    }
                }
                
                self.state = .completed
                self.progressDescription = "Done!"
                
            } catch let error as VideoCompatibilityError {
                self.videos = OrderedSet(self.videos.map { video in
                    var updatedVideo = video
                    if error.videoIds.contains(video.id) {
                        updatedVideo.hasError = true
                    }
                    return updatedVideo
                })
                self.state = .error(error.localizedDescription)
            } catch is CancellationError {
                self.state = .idle
                self.progressDescription = "Processing cancelled."
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Cancel task
    func cancelProcessing() {
        processingTask?.cancel()
        Task {
            await self.processor.cancel()
        }
    }
}
