//
//  VideoDropDelegate.swift
//  Splitter
//
//  Created by Edward Liaw on 3/3/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoDropDelegate: DropDelegate {
    let viewModel: AppViewModel
    @Binding var isTargeted: Bool

    // Called when a dragged item enters the drop area
    func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isTargeted = true
        }
    }

    // Called when the item leaves the drop area without dropping
    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isTargeted = false
        }
    }

    // Called when the user releases the drag
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        viewModel.addFiles(urls: [url])
                    }
                }
            }
        }
        return true
    }
}
