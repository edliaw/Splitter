//
//  ContentView.swift
//  Splitter
//
//  Created by Edward Liaw on 1/29/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            Text("Video Splitter")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            // Drag and Drop Area / List
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
                                    Text(video.name)
                                    Spacer()
                                }
                            }
                            .onMove(perform: viewModel.moveItems)
                        }
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    var urls: [URL] = []
                    let group = DispatchGroup()
                    
                    for provider in providers {
                        group.enter()
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url = url {
                                urls.append(url)
                            }
                            group.leave()
                        }
                    }
                    
                    group.notify(queue: .main) {
                        viewModel.addFiles(urls: urls)
                    }
                    return true
                }
                .padding(.horizontal)
                
                HStack {
                    Button(action: selectFiles) {
                        Label("Add Files", systemImage: "plus")
                    }
                    Spacer()
                    Button(action: { viewModel.videos.removeAll() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(viewModel.videos.isEmpty)
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // Controls
            Grid {
                GridRow {
                    Text("Folder:")
                        .gridColumnAlignment(.trailing)
                    HStack {
                        if let url = viewModel.outputDirectory {
                            Text(url.path)
                                .truncationMode(.middle)
                                .foregroundColor(.secondary)
                        } else {
                            Text("None Selected").foregroundColor(.red)
                        }
                        Spacer()
                        Button(action: viewModel.selectOutputDirectory) {
                            Label("Select", systemImage: "arrow.up.folder")
                        }
                    }
                    .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("Prefix:")
                    HStack {
                        TextField("some_prefix", text: $viewModel.filenamePrefix)
                            .multilineTextAlignment(.trailing)
                        Text("000.mp4")
                    }
                }
                GridRow {
                    Text("Length:")
                    HStack {
                        TextField("length", value: $viewModel.segmentSize, format: .number)
                            .multilineTextAlignment(.trailing)
                        Text("minutes")
                    }
                }
            }
            .padding(.horizontal)

            // Status and Progress
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
            
            // Action Button
            HStack {
                Spacer()
                
                Button(action: {
                    viewModel.startProcessing()
                }) {
                    Label("Merge & Split", systemImage: "play.rectangle")
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 300, minHeight: 600)
        
        // MARK: - Alert
        .alert(viewModel.alertTitle, isPresented: $viewModel.showingAlert, presenting: viewModel) { viewModel in
            Button("OK", role: .cancel) { }
        } message: { viewModel in
            Text(viewModel.alertMessage)
        }
    }
    
    var isProcessing: Bool {
        if case .processing = viewModel.state { return true }
        return false
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        
        if panel.runModal() == .OK {
            viewModel.addFiles(urls: panel.urls)
        }
    }
}

#Preview {
    ContentView()
}
