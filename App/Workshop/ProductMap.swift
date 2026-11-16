import BOMCore
import SwiftUI

/// The colours of the map and of the vendor bar: one per large vendor, grey for the rest.
enum VendorPalette {
    static let colours: [Color] = [
        Color(red: 0.239, green: 0.498, blue: 0.769),  // blue
        Color(red: 0.180, green: 0.620, blue: 0.576),  // teal
        Color(red: 0.851, green: 0.541, blue: 0.239),  // orange
        Color(red: 0.761, green: 0.337, blue: 0.431),  // rose
        Color(red: 0.455, green: 0.400, blue: 0.769),  // violet
    ]
    static let others = Color(red: 0.604, green: 0.639, blue: 0.663)
    static let group = Color(red: 0.604, green: 0.639, blue: 0.663).opacity(0.45)

    /// The five largest named vendors, in the order of "Who wrote it".
    static func top(_ a: WorkshopAnalysis) -> [String] {
        Array(a.composition.vendors.filter { !$0.unknown }.prefix(colours.count).map(\.label))
    }
}

/// "How it hangs together": the product in the middle, one ring per step away, a slice per part.
struct ProductMap: View {
    let model: DocumentModel
    let a: WorkshopAnalysis
    let map: DependencyMap
    let t: Typo

    @State private var hovered: Int?
    @State private var width: CGFloat = 900

    private var vendors: [String] { VendorPalette.top(a) }

    var body: some View {
        let side = min(max(320, width * 0.56), 680 * t.s)
        HStack(alignment: .top, spacing: t.pad(40)) {
            MapCanvas(map: map, colour: colour(of:), label: label(of:), hovered: $hovered, centre: centreLabel, t: t) { i in
                open(i)
            }
            .frame(width: side, height: side)
            .accessibilityElement()
            .accessibilityLabel(L("Map of the product: %d chosen directly, %d pulled in, up to %d steps deep.",
                                  a.composition.directCount ?? 0, a.composition.indirectCount ?? 0, map.rings))
            sideColumn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            if let ref = LaunchOptions.point { hovered = map.slices.firstIndex { $0.ref == ref } }
        }
    }

    // MARK: Right column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: t.pad(26)) {
            Group {
                if let hovered { card(hovered) } else {
                    Text(L("Point at a slice to see why it is there."))
                        .font(t.font(15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: t.pad(60), alignment: .leading)
                }
            }
            .frame(minHeight: t.pad(190), alignment: .top)
            legend
            VStack(alignment: .leading, spacing: t.pad(5)) {
                Text(L("Lighter: further from the product."))
                Text(L("A slice's width: the parts it stands for."))
                Text(L("Click a slice to open it."))
                if map.hiddenDeeper > 0 {
                    Text(L("%d parts deeper than %d steps are not drawn.", map.hiddenDeeper, map.rings))
                }
            }
            .font(t.font(13))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 460 * t.s, alignment: .leading)
        .padding(.top, t.pad(20))
    }

    private func card(_ i: Int) -> some View {
        let s = map.slices[i]
        return VStack(alignment: .leading, spacing: t.pad(8)) {
            if s.isGroup {
                Eyebrow(text: steps(s.depth), t: t)
                Text(L("%d more parts", s.groupCount)).font(t.font(24, .semibold))
                Text(L("Too narrow to draw one by one; together they stand for %d parts.", s.weight))
                    .font(t.font(14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(L("Click to list the parts on this ring →"))
                    .font(t.font(14)).foregroundStyle(Color.accentColor)
            } else if let ref = s.ref {
                let c = a.componentIndex(bomRef: ref).map { a.bom.components[$0] }
                Eyebrow(text: ([c?.type, c?.packageURL.map { OverviewView.ecosystemName($0.type) }].compactMap { $0 } + [steps(s.depth)])
                    .joined(separator: " · "), t: t)
                HStack(alignment: .firstTextBaseline, spacing: t.pad(8)) {
                    Text(c?.displayName ?? ref).font(t.font(24, .semibold)).lineLimit(2)
                    if let v = c?.version { Text(v).font(t.mono(15)).foregroundStyle(.secondary) }
                }
                Text(map.path(to: i).map { label(of: $0) }.joined(separator: " → "))
                    .font(t.font(14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let c {
                    HStack(spacing: t.pad(8)) {
                        let licences = c.licenses.map(\.label)
                        Pill(text: licences.isEmpty ? L("no licence stated") : licences.joined(separator: ", "),
                             kind: licences.isEmpty ? .gap : .neutral, t: t)
                        Pill(text: c.hashes.isEmpty ? L("no hash") : L("hash"), kind: c.hashes.isEmpty ? .gap : .neutral, t: t)
                    }
                    Text(L("Click to open the component →")).font(t.font(14)).foregroundStyle(Color.accentColor)
                } else {
                    Pill(text: L("not listed in components"), kind: .gap, t: t)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(t)
    }

    private var legend: some View {
        let groups = map.slices.contains { $0.isGroup }
        let otherCount = a.composition.vendors.filter { !$0.unknown }.count - vendors.count
        return VStack(alignment: .leading, spacing: t.pad(7)) {
            Eyebrow(text: L("Colour: vendor"), t: t)
            ForEach(Array(vendors.enumerated()), id: \.offset) { i, v in
                Button { model.showComponents(ComponentFilter(vendor: v)) } label: {
                    legendRow(VendorPalette.colours[i], v, a.composition.vendors.first { $0.label == v }?.count)
                }
                .buttonStyle(.plain)
            }
            if otherCount > 0 || a.composition.vendors.contains(where: \.unknown) {
                legendRow(VendorPalette.others, otherCount > 0 ? L("%d others", otherCount) : L("no vendor named"), nil)
            }
            if groups { legendRow(VendorPalette.group, L("merged: too narrow to draw"), nil) }
        }
    }

    private func legendRow(_ colour: Color, _ text: String, _ count: Int?) -> some View {
        HStack(spacing: t.pad(10)) {
            RoundedRectangle(cornerRadius: 3 * t.s).fill(colour).frame(width: t.pad(13), height: t.pad(13))
            Text(text).font(t.font(14)).lineLimit(1)
            if let count { Text("\(count)").font(t.font(14)).foregroundStyle(.secondary).monospacedDigit() }
        }
        .contentShape(Rectangle())
    }

    // MARK: Data

    private var centreLabel: String { a.bom.subject?.name ?? model.fileName ?? "" }

    private func steps(_ depth: Int) -> String {
        depth == 1 ? L("chosen directly") : L("%d steps from the product", depth)
    }

    private func component(_ i: Int) -> Component? {
        map.slices[i].ref.flatMap { a.componentIndex(bomRef: $0) }.map { a.bom.components[$0] }
    }

    func label(of i: Int) -> String {
        let s = map.slices[i]
        if s.isGroup { return L("%d more", s.groupCount) }
        return component(i)?.displayName ?? s.ref ?? ""
    }

    func colour(of i: Int) -> Color {
        let s = map.slices[i]
        if s.isGroup { return VendorPalette.group }
        guard let c = component(i), let v = Composition.vendor(of: c), let k = vendors.firstIndex(of: v) else { return VendorPalette.others }
        return VendorPalette.colours[k]
    }

    private func open(_ i: Int) {
        let s = map.slices[i]
        if s.isGroup {
            model.showComponents(ComponentFilter(depth: s.depth))
        } else if let ref = s.ref, let index = a.componentIndex(bomRef: ref) {
            model.openComponent(index)
        }
    }
}

/// The sunburst itself: drawing and hit testing.
private struct MapCanvas: View {
    let map: DependencyMap
    let colour: (Int) -> Color
    let label: (Int) -> String
    @Binding var hovered: Int?
    let centre: String
    let t: Typo
    let open: (Int) -> Void

    private struct Geometry {
        let centre: CGPoint
        let inner: CGFloat
        let ring: CGFloat
        init(_ size: CGSize, rings: Int) {
            let radius = min(size.width, size.height) / 2 - 4
            inner = radius * 0.19
            ring = min((radius - inner) / CGFloat(max(1, rings)), radius * 0.2)
            centre = CGPoint(x: size.width / 2, y: size.height / 2)
        }
        /// The ring (1…) and fraction of the circle under `p`; nil in the centre or outside.
        func locate(_ p: CGPoint) -> (depth: Int, fraction: Double)? {
            let dx = p.x - centre.x, dy = p.y - centre.y
            let r = hypot(dx, dy)
            guard r > inner else { return nil }
            var f = atan2(Double(dx), Double(-dy)) / (2 * .pi)
            if f < 0 { f += 1 }
            return (Int((r - inner) / ring) + 1, f)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let g = Geometry(geo.size, rings: map.rings)
            let path = hovered.map { Set(map.path(to: $0)) }
            Canvas { ctx, _ in
                draw(&ctx, g, path)
            }
            .onContinuousHover { phase in
                guard LaunchOptions.point == nil else { return }  // a snapshot keeps its chosen part
                switch phase {
                case .active(let p): hovered = g.locate(p).flatMap { map.slice(atDepth: $0.depth, fraction: $0.fraction) }
                case .ended: hovered = nil
                }
            }
            .onTapGesture { p in
                if let l = g.locate(p), let i = map.slice(atDepth: l.depth, fraction: l.fraction) { open(i) }
            }
            // The product's name in the middle, wrapped rather than cut.
            // Sized by the disc, not the text size, so a long name still fits at presentation size.
            let size = min(12 * t.s, g.inner * 0.17)
            VStack(spacing: 2) {
                Text(L("product")).font(.system(size: size * 0.85)).opacity(0.7)
                Text(centre).font(.system(size: size, weight: .semibold)).lineLimit(3).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color(nsColor: .textBackgroundColor))
            .frame(width: g.inner * 1.6)
            .position(g.centre)
            .allowsHitTesting(false)
        }
    }

    private func wedge(_ g: Geometry, _ s: DependencyMap.Slice) -> Path {
        let r0 = g.inner + CGFloat(s.depth - 1) * g.ring + 1.5
        let r1 = g.inner + CGFloat(s.depth) * g.ring - 1.5
        // 0 at the top, clockwise; SwiftUI angles start at 3 o'clock.
        let a0 = Angle.radians(s.start * 2 * .pi - .pi / 2), a1 = Angle.radians(s.end * 2 * .pi - .pi / 2)
        var p = Path()
        p.addArc(center: g.centre, radius: r1, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: g.centre, radius: r0, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }

    private func draw(_ ctx: inout GraphicsContext, _ g: Geometry, _ path: Set<Int>?) {
        let gap = Color(nsColor: .textBackgroundColor)
        for (i, s) in map.slices.enumerated() {
            let shape = wedge(g, s)
            let depthFade = max(0.45, 1 - 0.1 * Double(s.depth - 1))
            let dim = path.map { !$0.contains(i) } ?? false
            ctx.fill(shape, with: .color(colour(i).opacity(depthFade * (dim ? 0.22 : 1))))
            // A thin gap between neighbours; only where a slice is wide enough to show one.
            if (s.end - s.start) * 2 * .pi * Double(g.inner + CGFloat(s.depth) * g.ring) > 3 {
                ctx.stroke(shape, with: .color(gap), lineWidth: 1)
            }
        }
        if let h = hovered {
            ctx.stroke(wedge(g, map.slices[h]), with: .color(.primary), lineWidth: 2.5 * t.s)
        }
        // Names inside slices wide enough to hold them, on the first three rings, never overlapping.
        var placed: [CGRect] = []
        for (i, s) in map.slices.enumerated() where s.depth <= 3 {
            let mid = (s.start + s.end) / 2 * 2 * .pi
            let r = g.inner + (CGFloat(s.depth) - 0.5) * g.ring
            let arc = (s.end - s.start) * 2 * .pi * Double(r)
            let text = ctx.resolve(Text(shortName(label(i))).font(t.font(11, .semibold)).foregroundStyle(.white))
            let size = text.measure(in: CGSize(width: 400, height: 40))
            let full = s.end - s.start > 0.999
            guard full || Double(size.width) * 1.3 + 12 < arc, size.height + 4 < g.ring else { continue }
            if let path, !path.contains(i) { continue }
            let p = full ? CGPoint(x: g.centre.x, y: g.centre.y - r)
                         : CGPoint(x: g.centre.x + r * CGFloat(sin(mid)), y: g.centre.y - r * CGFloat(cos(mid)))
            let box = CGRect(x: p.x - size.width / 2 - 3, y: p.y - size.height / 2, width: size.width + 6, height: size.height)
            // Every corner of the label inside its own slice, so no name spills over an edge.
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
            guard corners.allSatisfy({ c in
                g.locate(c).map { $0.depth == s.depth && (full || (s.start <= $0.fraction && $0.fraction < s.end)) } ?? false
            }) else { continue }
            guard !placed.contains(where: { $0.intersects(box) }) else { continue }
            placed.append(box)
            ctx.draw(text, at: p)
        }
        // The product in the middle.
        let disc = Path(ellipseIn: CGRect(x: g.centre.x - g.inner + 2, y: g.centre.y - g.inner + 2,
                                          width: 2 * g.inner - 4, height: 2 * g.inner - 4))
        ctx.fill(disc, with: .color(.primary))

    }

    /// The name without its vendor, which the colour already says.
    private func shortName(_ s: String) -> String {
        s.split(separator: "/").last.map(String.init) ?? s
    }
}
