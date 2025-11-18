import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var image: NSImage?
    @State private var vectorArrows: [Arrow] = []

    @State private var brightBoundaryPoints: [CGPoint] = []
    @State private var darkBoundaryPoints: [CGPoint] = []

    @State private var showVectorDiagram: Bool = false

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
                    }
                }

                Button("Векторная диаграмма") {
                    if let img = image {
                        let vis = analyzeDomains(from: img, targetSize: canvasSize)
                        self.vectorArrows = vis.arrows
                        self.brightBoundaryPoints = vis.brightBoundaryPoints
                        self.darkBoundaryPoints = vis.darkBoundaryPoints
                        self.showVectorDiagram = true
                    }
                }
                .disabled(image == nil)
            }
            .padding(.top, 16)

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
