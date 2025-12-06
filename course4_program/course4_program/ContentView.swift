import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var image: NSImage?
    @State private var vectorArrows: [Arrow] = []

    @State private var brightBoundaryPoints: [CGPoint] = []
    @State private var darkBoundaryPoints: [CGPoint] = []

    @State private var showVectorDiagram: Bool = false

    // Кэш анализа изображения (яркость + базовые пороги Otsu)
    @State private var analysisCache: ImageAnalysisCache?

    // Ползунки: 0..1, где 0.5 = значение Otsu
    // При 0: порог×0.8, при 1: порог×1.2
    @State private var darkSlider: Double = 0.5
    @State private var brightSlider: Double = 0.5

    private let canvasSize: CGFloat = 400

    var body: some View {
        VStack(spacing: 16) {

            HStack(spacing: 12) {
                Button("Загрузить изображение") {
                    openImageFile { selectedImage in
                        self.image = selectedImage
                        self.vectorArrows = []
                        self.brightBoundaryPoints = []
                        self.darkBoundaryPoints = []
                        self.showVectorDiagram = false
                        self.analysisCache = nil
                        // Сброс ползунков на середину
                        self.darkSlider = 0.5
                        self.brightSlider = 0.5
                    }
                }

                Button("Векторная диаграмма") {
                    guard let img = image else { return }
                    
                    // Создаём кэш, если его ещё нет
                    if analysisCache == nil {
                        analysisCache = createAnalysisCache(from: img)
                    }
                    
                    guard let cache = analysisCache else { return }
                    
                    let vis = analyzeDomains(
                        cache: cache,
                        targetSize: canvasSize,
                        darkSlider: darkSlider,
                        brightSlider: brightSlider
                    )
                    self.vectorArrows = vis.arrows
                    self.brightBoundaryPoints = vis.brightBoundaryPoints
                    self.darkBoundaryPoints = vis.darkBoundaryPoints
                    self.showVectorDiagram = true
                }
                .disabled(image == nil)
            }
            .padding(.top, 16)

            // Ползунки для настройки порогов
            // 0 = base×0.8, 0.5 = base (Otsu), 1 = base×1.2
            VStack(spacing: 8) {
                HStack {
                    Text("Порог тёмных:")
                        .frame(width: 120, alignment: .leading)
                    Text("×0.80")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $darkSlider, in: 0...1)
                        .frame(width: 180)
                    Text("×1.20")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(sliderMultiplierText(darkSlider))
                        .frame(width: 50, alignment: .trailing)
                        .font(.caption)
                }

                HStack {
                    Text("Порог ярких:")
                        .frame(width: 120, alignment: .leading)
                    Text("×0.80")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $brightSlider, in: 0...1)
                        .frame(width: 180)
                    Text("×1.20")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(sliderMultiplierText(brightSlider))
                        .frame(width: 50, alignment: .trailing)
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            Divider()

            ScrollView {
                if let nsImage = image {
                    VStack(spacing: 24) {

                        VStack(spacing: 8) {
                            Text("Оригинал")
                                .foregroundColor(.secondary)

                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: canvasSize, height: canvasSize)
                                .border(Color.gray)
                        }

                        if showVectorDiagram {

                            VStack(spacing: 8) {
                                Text("Границы доменов")
                                    .foregroundColor(.secondary)

                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: canvasSize, height: canvasSize)
                                    .overlay(
                                        DomainBoundaryView(
                                            brightPoints: brightBoundaryPoints,
                                            darkPoints: darkBoundaryPoints
                                        )
                                        .frame(width: canvasSize, height: canvasSize)
                                        .allowsHitTesting(false)
                                    )
                                    .border(Color.blue)
                            }

                            VStack(spacing: 8) {
                                Text("Векторное поле")
                                    .foregroundColor(.secondary)

                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: canvasSize, height: canvasSize)
                                    .overlay(
                                        ArrowFieldView(arrows: vectorArrows)
                                            .frame(width: canvasSize, height: canvasSize)
                                            .allowsHitTesting(false)
                                    )
                                    .border(Color.blue)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                } else {
                    Text("Файл не выбран")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 800)
        .padding()
    }
}

struct Arrow {
    var start: CGPoint
    var end: CGPoint
    var color: Color
}

struct ArrowFieldView: View {
    var arrows: [Arrow]

    var body: some View {
        Canvas { context, size in
            for arrow in arrows {
                var path = Path()
                path.move(to: arrow.start)
                path.addLine(to: arrow.end)
                context.stroke(path, with: .color(arrow.color), lineWidth: 2)
            }
        }
    }
}

struct DomainBoundaryView: View {
    var brightPoints: [CGPoint] // зелёные
    var darkPoints: [CGPoint]   // красные

    var body: some View {
        Canvas { context, size in
            let dotSize: CGFloat = 2.0

            for p in brightPoints {
                let rect = CGRect(
                    x: p.x - dotSize / 2,
                    y: p.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: rect), with: .color(.green))
            }

            for p in darkPoints {
                let rect = CGRect(
                    x: p.x - dotSize / 2,
                    y: p.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: rect), with: .color(.red))
            }
        }
    }
}

/// Форматирование множителя для отображения
func sliderMultiplierText(_ slider: Double) -> String {
    let multiplier = 0.8 + slider * 0.4
    return String(format: "×%.2f", multiplier)
}

func openImageFile(completion: @escaping (NSImage?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    if panel.runModal() == .OK,
       let url = panel.url,
       let nsImage = NSImage(contentsOf: url) {
        completion(nsImage)
    } else {
        completion(nil)
    }
}
