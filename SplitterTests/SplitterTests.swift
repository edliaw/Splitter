//
//  SplitterTests.swift
//  SplitterTests
//
//  Created by Edward Liaw on 3/4/26.
//

import Testing
import Foundation
@testable import Splitter

func createMockConfig(videoCount: Int) -> VideoProcessorConfig {
    var videos: [InputVideo] = []
    for i in 0..<videoCount {
        videos.append(InputVideo(id: URL(fileURLWithPath: "/tmp/video\(i).mp4")))
    }
    return VideoProcessorConfig(
        segmentSize: 10.0,
        splitEnabled: true,
        startNumberStr: "000",
        filenamePrefix: "test",
        outputDirectory: URL(fileURLWithPath: "/tmp"),
        videos: videos
    )
}

struct SplitterTests {
    @Suite struct FunctionTests {
        
        @Test func timeStringToSeconds_standard() {
            let result = timeStringToSeconds("01:02:03.004")
            #expect(result == 3723.004)
        }
        
        @Test func timeStringToSeconds_noHours() {
            let result = timeStringToSeconds("02:03")
            #expect(result == 123)
        }
        
        @Test func timeStringToSeconds_negative() {
            let result = timeStringToSeconds("-01:02:03")
            #expect(result == nil)
        }
    }
        
    @Suite class VideoProcessorTests {
        var processor: VideoProcessor!
        
        init() {
            processor = VideoProcessor()
        }
        
        deinit {
            processor = nil
        }
        
        @Test func checkCompatAndTotalDuration_success() throws {
            let config = createMockConfig(videoCount: 2)
            
            let stream1 = FFprobeOutput.Stream(codec_type: "video", codec_name: "h264", width: 1920, height: 1080, sample_rate: nil)
            let stream2 = FFprobeOutput.Stream(codec_type: "audio", codec_name: "aac", width: nil, height: nil, sample_rate: "44100")
            
            let output1 = FFprobeOutput(streams: [stream1, stream2], format: FFprobeOutput.Format(duration: "10.0"))
            let output2 = FFprobeOutput(streams: [stream1, stream2], format: FFprobeOutput.Format(duration: "15.0"))
            
            let totalDuration = try processor.checkCompatAndTotalDuration(config: config, outputs: [output1, output2])
            
            #expect(totalDuration == 25.0, "Total duration should be the sum of both videos")
        }
        
        @Test func checkCompatAndTotalDuration_incompatibleCodecs() throws {
            let config = createMockConfig(videoCount: 4)
            
            let stream1 = FFprobeOutput.Stream(codec_type: "video", codec_name: "h264", width: 1920, height: 1080, sample_rate: nil)
            let stream2 = FFprobeOutput.Stream(codec_type: "video", codec_name: "hevc", width: 1920, height: 1080, sample_rate: nil)
            let stream3 = stream1
            let stream4 = stream2

            let output1 = FFprobeOutput(streams: [stream1], format: FFprobeOutput.Format(duration: "10.0"))
            let output2 = FFprobeOutput(streams: [stream2], format: FFprobeOutput.Format(duration: "15.0"))
            let output3 = FFprobeOutput(streams: [stream3], format: FFprobeOutput.Format(duration: "20.0"))
            let output4 = FFprobeOutput(streams: [stream4], format: FFprobeOutput.Format(duration: "25.0"))

            let error = #expect(throws: VideoCompatibilityError.self) {
                try processor.checkCompatAndTotalDuration(config: config, outputs: [output1, output2, output3, output4])
            }
            
            #expect(error?.videoIds == Set([config.videos[1].id, config.videos[3].id]), "Videos 1 and 3 should be incompatible")
        }
    }
    
    @Suite @MainActor class AppModelTests {
        var viewModel: AppViewModel!
        
        init() {
            viewModel = AppViewModel()
        }
        
        deinit {
            viewModel = nil
        }
        
        @Test func addFiles_onlyMp4() {
            let validURL = URL(fileURLWithPath: "/path/to/video.mp4")
            let invalidURL1 = URL(fileURLWithPath: "/path/to/audio.mp3")
            let invalidURL2 = URL(fileURLWithPath: "/path/to/document.pdf")
            
            viewModel.addFiles(urls: [validURL, invalidURL1, invalidURL2])
            
            #expect(viewModel.videos.count == 1, "Only mp4 files should be added")
            #expect(viewModel.videos.first?.id == validURL)
        }
        
        @Test func deleteItem_success() {
            let url1 = URL(fileURLWithPath: "/path/to/video1.mp4")
            let url2 = URL(fileURLWithPath: "/path/to/video2.mp4")
            
            viewModel.addFiles(urls: [url1, url2])
            let videoToDelete = viewModel.videos.first(where: { $0.id == url1 })!
            viewModel.deleteItem(video: videoToDelete)
            
            #expect(viewModel.videos.count == 1, "First video should be deleted")
            #expect(viewModel.videos.first?.id == url2)
        }
        
        @Test func moveItems_success() {
            let url1 = URL(fileURLWithPath: "/path/to/video1.mp4")
            let url2 = URL(fileURLWithPath: "/path/to/video2.mp4")
            let url3 = URL(fileURLWithPath: "/path/to/video3.mp4")
            
            viewModel.addFiles(urls: [url1, url2, url3])
            viewModel.moveItems(from: IndexSet(integer: 0), to: 3)
            
            #expect(viewModel.videos.map { $0.id } == [url2, url3, url1], "Videos should be reordered 2, 3, 1")
        }
        
        @Test func isFFmpegInstalled_success() {
            #expect(viewModel.isFFmpegInstalled())
        }
    }
}
