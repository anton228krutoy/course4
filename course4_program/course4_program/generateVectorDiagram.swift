//
//  generateVectorDiagram.swift
//  course4_program
//

import SwiftUI
import AppKit

struct DomainVisualization {
    let arrows: [Arrow]
    let brightBoundaryPoints: [CGPoint]  // границы светлых доменов
    let darkBoundaryPoints: [CGPoint]    // границы тёмных доменов
}

func analyzeDomains(from image: NSImage,
                    targetSize: CGFloat = 400) -> DomainVisualization {

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return DomainVisualization(
            arrows: [],
            brightBoundaryPoints: [],
            darkBoundaryPoints: []
        )
    }

    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh

    func brightnessAt(x: Int, y: Int) -> Double? {
        guard
            let color = bitmap.colorAt(x: x, y: y)?
                .usingColorSpace(NSColorSpace.deviceRGB)
        else { return nil }

        let r = Double(color.redComponent)
        let g = Double(color.greenComponent)
        let b = Double(color.blueComponent)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    var brightness: [[Double]] = Array(
        repeating: Array(repeating: 0.0, count: width),
        count: height
    )

    var minB = 1.0
    var maxB = 0.0

    for y in 0..<height {
        for x in 0..<width {
            if let br = brightnessAt(x: x, y: y) {
                brightness[y][x] = br
                if br < minB { minB = br }
                if br > maxB { maxB = br }
            }
        }
    }

    if maxB <= minB {
        return DomainVisualization(
            arrows: [],
            brightBoundaryPoints: [],
            darkBoundaryPoints: []
        )
    }

    let range = maxB - minB
    let tDark = minB + 0.50 * range      // тёмные домены
    let tBright = minB + 0.75 * range    // светлые домены

    struct Domain {
        var points: [(Int, Int)]
        var isBright: Bool
        var index: Int
    }

    var labels = Array(
        repeating: Array(repeating: -1, count: width),
        count: height
    )

    var domains: [Domain] = []

    let neighbors = [
        (dx: 1,  dy: 0),
        (dx: -1, dy: 0),
        (dx: 0,  dy: 1),
        (dx: 0,  dy: -1)
    ]

    for y in 0..<height {
        for x in 0..<width {
            let br = brightness[y][x]
            let isBright = br >= tBright
            let isDark = br <= tDark

            if !(isBright || isDark) { continue }
            if labels[y][x] != -1 { continue }

            let classIsBright = isBright
            let labelIndex = domains.count

            var queue: [(Int, Int)] = []
            var pts: [(Int, Int)] = []

            labels[y][x] = labelIndex
            queue.append((x, y))

            while !queue.isEmpty {
                let (cx, cy) = queue.removeFirst()
                pts.append((cx, cy))

                for n in neighbors {
                    let nx = cx + n.dx
                    let ny = cy + n.dy

                    if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                    if labels[ny][nx] != -1 { continue }

                    let nbr = brightness[ny][nx]
                    let nIsBright = nbr >= tBright
                    let nIsDark = nbr <= tDark

                    if classIsBright {
                        if !nIsBright { continue }
                    } else {
                        if !nIsDark { continue }
                    }

                    labels[ny][nx] = labelIndex
                    queue.append((nx, ny))
                }
            }

            domains.append(
                Domain(points: pts, isBright: classIsBright, index: labelIndex)
            )
        }
    }

    let minDomainPixels = max(50, (width * height) / 5000)
    let filteredDomains = domains.filter { $0.points.count >= minDomainPixels }

    let scaleX = targetSize / CGFloat(width)
    let scaleY = targetSize / CGFloat(height)

    var arrows: [Arrow] = []
    var brightBoundaryPoints: [CGPoint] = []
    var darkBoundaryPoints: [CGPoint] = []

    // Границы доменов
    for domain in filteredDomains {
        let labelIndex = domain.index

        for (x, y) in domain.points {
            var isBoundary = false

            for n in neighbors {
                let nx = x + n.dx
                let ny = y + n.dy

                if nx < 0 || nx >= width || ny < 0 || ny >= height {
                    isBoundary = true
                    break
                }

                if labels[ny][nx] != labelIndex {
                    isBoundary = true
                    break
                }
            }

            if isBoundary {
                let px = CGFloat(x) * scaleX
                let py = CGFloat(y) * scaleY
                let p = CGPoint(x: px, y: py)

                if domain.isBright {
                    brightBoundaryPoints.append(p)   // зелёные
                } else {
                    darkBoundaryPoints.append(p)     // красные
                }
            }
        }
    }

    // Векторы (пока просто оставляем как было)
    let baseLength: CGFloat = 40

    for domain in filteredDomains {
        var sumX = 0.0
        var sumY = 0.0

        for (x, y) in domain.points {
            sumX += Double(x)
            sumY += Double(y)
        }

        let count = Double(domain.points.count)
        let cx = sumX / count
        let cy = sumY / count

        let sx = CGFloat(cx) * scaleX
        let sy = CGFloat(cy) * scaleY

        let dir: CGFloat = domain.isBright ? 1.0 : -1.0
        let ex = sx
        let ey = sy + dir * baseLength

        let color: Color = domain.isBright ? .red : .blue

        arrows.append(
            Arrow(
                start: CGPoint(x: sx, y: sy),
                end: CGPoint(x: ex, y: ey),
                color: color
            )
        )
    }

    return DomainVisualization(
        arrows: arrows,
        brightBoundaryPoints: brightBoundaryPoints,
        darkBoundaryPoints: darkBoundaryPoints
    )
}
