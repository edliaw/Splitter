//
//  ContentView.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import SwiftUI
import UniformTypeIdentifiers
internal import OrderedCollections

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isTargeted = false
    
    @AppStorage("outputDirectory") private var outputDirectory: URL?
    @AppStorage("filenamePrefix") private var filenamePrefix: String = ""
    @AppStorage("segmentSize") private var segmentSize: Double = 10.0
    @State private var startNumberStr: String = "000"
    @State private var splitEnabled: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            Text("Video Splitter")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            VideoListView(viewModel: viewModel, isTargeted: $isTargeted)
            
            Divider()
            
            ControlsView(
                viewModel: viewModel,
                outputDirectory: $outputDirectory,
                filenamePrefix: $filenamePrefix,
                startNumberStr: $startNumberStr,
                splitEnabled: $splitEnabled,
                segmentSize: $segmentSize
            )
            
            StatusView(viewModel: viewModel)

            ActionButtonView(
                viewModel: viewModel,
                outputDirectory: $outputDirectory,
                filenamePrefix: $filenamePrefix,
                startNumberStr: $startNumberStr,
                splitEnabled: $splitEnabled,
                segmentSize: $segmentSize
            )
        }
        .frame(minWidth: 300, idealWidth: 400, minHeight: 550, idealHeight: 600)
        
        // MARK: - Alerts
        .alert(viewModel.alertTitle, isPresented: $viewModel.showingAlert, presenting: viewModel) { viewModel in
            Button("OK", role: .cancel) { }
        } message: { viewModel in
            Text(viewModel.alertMessage)
        }
    }
}

// MARK: - Drag and Drop Area / List
struct VideoListView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isTargeted: Bool
    
    var body: some View {
        VStack {
            VStack {
                if viewModel.videos.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isTargeted ? Color.accentColor : Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        
                        VStack {
                            Image(systemName: "arrow.down.doc")
                                .font(.largeTitle)
                            Text("Drag and drop MP4 files here")
                        }
                        .foregroundColor(.secondary)
                    }
                    .frame(height: 200)
                } else {
                    List {
                        ForEach(viewModel.videos) { video in
                            HStack {
                                Image(systemName: "film")
                                    .foregroundColor(video.hasError ? .red : .primary)
                                Text(video.name)
                                    .foregroundColor(video.hasError ? .red : .primary)
                                Spacer()
                                Button(action: {
                                    viewModel.deleteItem(video: video)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .onMove(perform: viewModel.moveItems)
                    }
                    .frame(minHeight: 50, idealHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
            }
            .onDrop(of: [.mpeg4Movie], delegate: VideoDropDelegate(viewModel: viewModel, isTargeted: $isTargeted))
            .padding(.horizontal)
            
            HStack {
                Button(action: selectFiles) {
                    Label("Add Files", systemImage: "plus")
                }
                Spacer()
                Button(action: { viewModel.videos.removeAll() }) {
                    Label("Clear", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .disabled(viewModel.videos.isEmpty)
            }
            .padding(.horizontal)
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mpeg4Movie]
        
        if panel.runModal() == .OK {
            viewModel.addFiles(urls: panel.urls)
        }
    }
}

// MARK: - Controls
struct ControlsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var outputDirectory: URL?
    @Binding var filenamePrefix: String
    @Binding var startNumberStr: String
    @Binding var splitEnabled: Bool
    @Binding var segmentSize: Double
    
    var body: some View {
        Grid {
            GridRow {
                Text("Folder:")
                    .gridColumnAlignment(.trailing)
                HStack {
                    if let url = outputDirectory {
                        Text(url.path)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                    } else {
                        Text("None Selected").foregroundColor(.red)
                    }
                    Spacer()
                    Button(action: {
                        if let selectedURL = viewModel.selectOutputDirectory() {
                            outputDirectory = selectedURL
                        }
                    }) {
                        Label("Select", systemImage: "arrow.up.folder")
                    }
                }
                .gridColumnAlignment(.leading)
            }
            GridRow {
                Text("Output:")
                HStack {
                    TextField("filename prefix", text: $filenamePrefix)
                        .multilineTextAlignment(.trailing)
                    if splitEnabled {
                        TextField("start", text: $startNumberStr)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 40)
                            .onChange(of: startNumberStr) { oldValue, newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if let number = UInt16(String(filtered)) {
                                    startNumberStr = String(format: "%03d", number)
                                } else {
                                    startNumberStr = "000"
                                }
                            }
                    }
                    Text(".mp4")
                }
            }
            GridRow {
                Text("Mode:")
                HStack {
                    if splitEnabled {
                        Text("Split")
                    } else {
                        Text("Merge")
                    }
                    Spacer()
                    Toggle("", isOn: $splitEnabled)
                        .toggleStyle(.switch)
                        .multilineTextAlignment(.trailing)
                }
            }
            if splitEnabled {
                GridRow {
                    Text("Length:")
                    HStack {
                        TextField("length", value: $segmentSize, format: .number)
                            .multilineTextAlignment(.trailing)
                        Text("minutes")
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Status and Progress
struct StatusView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        VStack {
            switch viewModel.state {
            case .idle:
                EmptyView()
            case .processing(let progress):
                ProgressView(value: progress)
                Text(viewModel.progressDescription)
                    .font(.caption)
            case .completed:
                Text("Completed Successfully!")
                    .foregroundColor(.green)
            case .error(let msg):
                Text("Error: \(msg)")
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Action Button
struct ActionButtonView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var outputDirectory: URL?
    @Binding var filenamePrefix: String
    @Binding var startNumberStr: String
    @Binding var splitEnabled: Bool
    @Binding var segmentSize: Double
    
    var body: some View {
        HStack {
            Spacer()
            
            switch viewModel.state {
            case .processing:
                Button(action: {
                    viewModel.cancelProcessing()
                }) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                }
            default:
                Button(action: {
                    viewModel.startProcessing(
                        outputDirectory: outputDirectory,
                        filenamePrefix: filenamePrefix,
                        startNumberStr: startNumberStr,
                        segmentSize: segmentSize,
                        splitEnabled: splitEnabled
                    )
                }) {
                    if splitEnabled {
                        Label("Merge & Split", systemImage: "play.rectangle")
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                    } else {
                        Label("Merge", systemImage: "play.rectangle")
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
