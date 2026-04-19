import Foundation
import CoreGraphics
import ImageIO

func floodFillTransparency(atPath path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dataProvider = CGDataProvider(url: url as CFURL),
          let imageSource = CGImageSourceCreateWithDataProvider(dataProvider, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("Failed to load: \(path)")
        return
    }

    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
        print("Failed context: \(path)")
        return
    }
    
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    guard let pixelData = context.data else {
        print("No data: \(path)")
        return
    }
    
    let bytesPerRow = context.bytesPerRow
    let pixels = pixelData.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

    // Identify background color at (0,0)
    let bR = pixels[0]
    let bG = pixels[1]
    let bB = pixels[2]
    
    print("Detected BG Color at 0,0: (\(bR), \(bG), \(bB))")

    var visited = Set<Int>()
    var queue = [Int]()

    // Add corners and edges
    let corners = [
        (0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)
    ]
    
    for (cx, cy) in corners {
        queue.append(cy * width + cx)
    }

    while !queue.isEmpty {
        let currentIdx = queue.removeFirst()
        if visited.contains(currentIdx) { continue }
        visited.insert(currentIdx)

        let x = currentIdx % width
        let y = currentIdx / width
        let offset = (y * bytesPerRow) + (x * 4)

        let r = pixels[offset]
        let g = pixels[offset + 1]
        let b = pixels[offset + 2]

        // Similarity check (Match background color with tolerance)
        let tolerance: Int = 30
        let matches = abs(Int(r) - Int(bR)) < tolerance && 
                      abs(Int(g) - Int(bG)) < tolerance && 
                      abs(Int(b) - Int(bB)) < tolerance

        if matches {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0

            // Check Neighbors (4-way)
            let neighbors = [(x-1, y), (x+1, y), (x, y-1), (x, y+1)]
            for (nx, ny) in neighbors {
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let nIdx = ny * width + nx
                    if !visited.contains(nIdx) {
                        queue.append(nIdx)
                    }
                }
            }
        }
    }

    guard let finalImage = context.makeImage() else {
        print("Failed final: \(path)")
        return
    }

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed dest: \(path)")
        return
    }

    CGImageDestinationAddImage(destination, finalImage, nil)
    if CGImageDestinationFinalize(destination) {
        print("Cleaned: \(path)")
    } else {
        print("Failed save: \(path)")
    }
}

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath
let asset = "mods/tdm_core/textures/tdm_logo_red.png"
let fullPath = "\(currentPath)/\(asset)"

if fileManager.fileExists(atPath: fullPath) {
    floodFillTransparency(atPath: fullPath)
} else {
    print("File not found: \(fullPath)")
}
