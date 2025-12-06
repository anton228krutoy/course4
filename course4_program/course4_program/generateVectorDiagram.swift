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

/// Кэш для хранения данных анализа изображения
class ImageAnalysisCache {
    let brightness: [[Double]]
    let width: Int
    let height: Int
    let minB: Double
    let maxB: Double
    let range: Double
    
    // Базовые пороги, рассчитанные методом Otsu (абсолютные значения яркости)
    let baseDarkThreshold: Double
    let baseBrightThreshold: Double
    
    init(brightness: [[Double]], width: Int, height: Int, minB: Double, maxB: Double,
         baseDarkThreshold: Double, baseBrightThreshold: Double) {
        self.brightness = brightness
        self.width = width
        self.height = height
        self.minB = minB
        self.maxB = maxB
        self.range = maxB - minB
        self.baseDarkThreshold = baseDarkThreshold
        self.baseBrightThreshold = baseBrightThreshold
    }
}

/// Применение линейного множителя к порогу
/// slider: 0..1, где 0.5 = базовое значение
/// При slider=0: threshold*0.8, при slider=1: threshold*1.2
func applySliderMultiplier(baseValue: Double, slider: Double) -> Double {
    // multiplier = 0.8 + slider * 0.4
    // slider=0 -> 0.8, slider=0.5 -> 1.0, slider=1 -> 1.2
    let multiplier = 0.8 + slider * 0.4
    return baseValue * multiplier
}

/// Двухпороговый метод Otsu для разделения на 3 класса: тёмные, нейтральные, светлые
/// Возвращает два порога (в диапазоне 0.0...1.0)
/// trimPercent - процент крайних значений для отбрасывания (по 5% с каждой стороны)
func otsuDualThreshold(brightness: [[Double]], width: Int, height: Int, trimPercent: Double = 0.05) -> (dark: Double, bright: Double) {
    let numBins = 256
    var histogram = [Int](repeating: 0, count: numBins)
    var totalPixels = 0

    // Построение полной гистограммы для определения перцентилей
    for y in 0..<height {
        for x in 0..<width {
            let br = brightness[y][x]
            let bin = min(numBins - 1, max(0, Int(br * Double(numBins - 1))))
            histogram[bin] += 1
            totalPixels += 1
        }
    }

    guard totalPixels > 0 else {
        return (dark: 0.33, bright: 0.66)
    }

    // Вычисление перцентилей для отбрасывания крайних значений
    let trimCount = Int(Double(totalPixels) * trimPercent)
    var lowBin = 0
    var highBin = numBins - 1
    
    // Найти нижний порог (отбросить trimPercent самых тёмных)
    var cumSum = 0
    for i in 0..<numBins {
        cumSum += histogram[i]
        if cumSum >= trimCount {
            lowBin = i
            break
        }
    }
    
    // Найти верхний порог (отбросить trimPercent самых ярких)
    cumSum = 0
    for i in stride(from: numBins - 1, through: 0, by: -1) {
        cumSum += histogram[i]
        if cumSum >= trimCount {
            highBin = i
            break
        }
    }
    
    // Построение обрезанной гистограммы (без крайних 5%)
    var trimmedHistogram = [Int](repeating: 0, count: numBins)
    var trimmedTotalPixels = 0
    
    for i in lowBin...highBin {
        trimmedHistogram[i] = histogram[i]
        trimmedTotalPixels += histogram[i]
    }
    
    guard trimmedTotalPixels > 0 else {
        return (dark: 0.33, bright: 0.66)
    }

    // Вычисление кумулятивных сумм для оптимизации (используем обрезанную гистограмму)
    var prob = [Double](repeating: 0, count: numBins)      // P(i)
    var cumProb = [Double](repeating: 0, count: numBins)   // omega(k)
    var cumMean = [Double](repeating: 0, count: numBins)   // mu(k)

    for i in 0..<numBins {
        prob[i] = Double(trimmedHistogram[i]) / Double(trimmedTotalPixels)
    }

    cumProb[0] = prob[0]
    cumMean[0] = 0

    for i in 1..<numBins {
        cumProb[i] = cumProb[i - 1] + prob[i]
        cumMean[i] = cumMean[i - 1] + Double(i) * prob[i]
    }

    let totalMean = cumMean[numBins - 1]

    // Поиск оптимальных порогов методом полного перебора
    var maxVariance = -1.0
    var bestT1 = numBins / 3
    var bestT2 = 2 * numBins / 3

    // Перебор всех пар порогов (с шагом для ускорения)
    let step = max(1, numBins / 64)  // Оптимизация: не проверять каждый бин
    
    for t1 in stride(from: 1, to: numBins - 2, by: step) {
        for t2 in stride(from: t1 + 1, to: numBins - 1, by: step) {
            // Веса классов
            let w0 = cumProb[t1]
            let w1 = cumProb[t2] - cumProb[t1]
            let w2 = 1.0 - cumProb[t2]

            // Пропуск вырожденных случаев
            if w0 <= 0 || w1 <= 0 || w2 <= 0 { continue }

            // Средние значения классов
            let mu0 = cumMean[t1] / w0
            let mu1 = (cumMean[t2] - cumMean[t1]) / w1
            let mu2 = (totalMean - cumMean[t2]) / w2

            // Межклассовая дисперсия
            let variance = w0 * (mu0 - totalMean) * (mu0 - totalMean) +
                          w1 * (mu1 - totalMean) * (mu1 - totalMean) +
                          w2 * (mu2 - totalMean) * (mu2 - totalMean)

            if variance > maxVariance {
                maxVariance = variance
                bestT1 = t1
                bestT2 = t2
            }
        }
    }

    // Конвертация индексов бинов в значения яркости (0.0...1.0)
    let darkThreshold = Double(bestT1) / Double(numBins - 1)
    let brightThreshold = Double(bestT2) / Double(numBins - 1)

    return (dark: darkThreshold, bright: brightThreshold)
}

/// Создание кэша анализа изображения (расчёт яркости и порогов Otsu)
func createAnalysisCache(from image: NSImage) -> ImageAnalysisCache? {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
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

    guard maxB > minB else {
        return nil
    }

    // Нормализация яркости для метода Otsu
    let range = maxB - minB
    var normalizedBrightness: [[Double]] = Array(
        repeating: Array(repeating: 0.0, count: width),
        count: height
    )
    for y in 0..<height {
        for x in 0..<width {
            normalizedBrightness[y][x] = (brightness[y][x] - minB) / range
        }
    }

    // Расчёт порогов методом Otsu
    let thresholds = otsuDualThreshold(brightness: normalizedBrightness, width: width, height: height)
    
    // Конвертация нормализованных порогов в абсолютные значения яркости
    let baseDarkThreshold = minB + thresholds.dark * range
    let baseBrightThreshold = minB + thresholds.bright * range

    return ImageAnalysisCache(
        brightness: brightness,
        width: width,
        height: height,
        minB: minB,
        maxB: maxB,
        baseDarkThreshold: baseDarkThreshold,
        baseBrightThreshold: baseBrightThreshold
    )
}

/// Анализ доменов с использованием кэша и логарифмических ползунков
/// darkSlider, brightSlider: 0..1, где 0.5 = базовое значение Otsu
func analyzeDomains(cache: ImageAnalysisCache,
                    targetSize: CGFloat = 400,
                    darkSlider: Double = 0.5,
                    brightSlider: Double = 0.5) -> DomainVisualization {

    let width = cache.width
    let height = cache.height
    let brightness = cache.brightness

    // Применение множителей ползунков к базовым порогам
    let tDark = applySliderMultiplier(baseValue: cache.baseDarkThreshold, slider: darkSlider)
    let tBright = applySliderMultiplier(baseValue: cache.baseBrightThreshold, slider: brightSlider)

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

    // Расчёт соотношения сторон для корректного отображения с scaledToFit()
    let imageAspect = CGFloat(width) / CGFloat(height)
    var displayWidth: CGFloat
    var displayHeight: CGFloat
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    if imageAspect > 1.0 {
        // Горизонтальное изображение - ограничено по ширине
        displayWidth = targetSize
        displayHeight = targetSize / imageAspect
        offsetY = (targetSize - displayHeight) / 2
    } else {
        // Вертикальное изображение - ограничено по высоте
        displayHeight = targetSize
        displayWidth = targetSize * imageAspect
        offsetX = (targetSize - displayWidth) / 2
    }

    let scaleX = displayWidth / CGFloat(width)
    let scaleY = displayHeight / CGFloat(height)

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
                let px = CGFloat(x) * scaleX + offsetX
                let py = CGFloat(y) * scaleY + offsetY
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

        let sx = CGFloat(cx) * scaleX + offsetX
        let sy = CGFloat(cy) * scaleY + offsetY

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
