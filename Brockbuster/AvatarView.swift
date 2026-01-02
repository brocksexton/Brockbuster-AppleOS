//
//  AvatarView.swift
//  Brockbuster
//
//  Created by Brock Sexton on 2025-12-31.
//

import SwiftUI

struct AvatarView: View {
    let urlString: String?
    let fallbackText: String

    var body: some View {
        ZStack {
            Circle().fill(BrockbusterTheme.brockLight.opacity(0.12))

            if let s = urlString, let url = URL(string: s) {
                BBCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(fallbackText)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
                    }
                }
                .clipShape(Circle())
            } else {
                Text(fallbackText)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(BrockbusterTheme.brockLight.opacity(0.9))
            }
        }
        .clipShape(Circle())
    }
}
