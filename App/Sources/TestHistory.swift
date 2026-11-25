import SwiftUI
import WorkoutCore

/*
 * Tests (his pick 34, round 28): threshold pulse, bike power and swim pace
 * for every test entered, as three small dot charts — large dots, faint
 * lines, the newest value as the big figure beside its name, each dot's day
 * under it. Equal results sit at the same height and the grey line says so
 * ("Steady since Test 1"); the app never says whether a result is better.
 */
struct TestHistoryCard: View {
    let tests: [TestResult]

    var body: some View {
        let series = TestHistory.series(tests)
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tests").font(.headline).foregroundStyle(Theme.progress)
                ForEach(series) { s in
                    ProgTile(name: s.measure.title, id: "test-series-\(s.measure.rawValue)") {
                        if let n = s.newest {
                            ProgFigure(figure: s.measure.text(n.value), unit: s.measure.unit)
                        }
                        ProgNote(text: s.line)
                        DotChart(dots: s.dots).padding(.top, 6)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tests-card")
        }
    }
}

/* Large dots, faint lines, the day under each dot. Equal values stand at the same height. */
private struct DotChart: View {
    let dots: [TestHistory.Dot]
    private let height: CGFloat = 54
    private let radius: CGFloat = 7

    var body: some View {
        VStack(spacing: 3) {
            Canvas { ctx, size in
                let values = dots.map(\.value)
                let lo = values.min() ?? 0, hi = values.max() ?? 0
                func point(_ i: Int) -> CGPoint {
                    let x = size.width * (CGFloat(i) + 0.5) / CGFloat(dots.count)
                    let y = hi > lo ? size.height - radius - (size.height - 2 * radius) * CGFloat((dots[i].value - lo) / (hi - lo)) : size.height / 2
                    return CGPoint(x: x, y: y)
                }
                var line = Path()
                for i in dots.indices { i == 0 ? line.move(to: point(i)) : line.addLine(to: point(i)) }
                ctx.stroke(line, with: .color(Theme.progress.opacity(0.28)), lineWidth: 1.5)
                for i in dots.indices {
                    let p = point(i)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(Theme.progress))
                }
            }
            .frame(height: height)
            HStack(spacing: 0) {
                ForEach(dots) { d in
                    Text(d.label).font(.caption2).foregroundStyle(Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dots.map { "\($0.test) \($0.label)" }.joined(separator: ", "))
    }
}
