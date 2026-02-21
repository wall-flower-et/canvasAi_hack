import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [NSImage] = []
    @State private var promptExpanded: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var groups: [CardGroup] = [
        CardGroup(id: "travel", title: "Travel", color: Color(red: 76/255, green: 175/255, blue: 80/255), cards: [
            CardData(id: "tokyo", title: "Tokyo", icon: "building.2"),
            CardData(id: "kyoto", title: "Kyoto", icon: "leaf"),
            CardData(id: "osaka", title: "Osaka", icon: "fork.knife"),
        ]),
        CardGroup(id: "food", title: "Food", color: Color(red: 222/255, green: 115/255, blue: 86/255), cards: [
            CardData(id: "ramen", title: "Ramen", icon: "cup.and.saucer"),
            CardData(id: "sushi", title: "Sushi", icon: "fish"),
        ]),
        CardGroup(id: "budget", title: "Budget", color: Color(red: 66/255, green: 133/255, blue: 244/255), cards: [
            CardData(id: "flights", title: "Flights", icon: "airplane"),
            CardData(id: "hotels", title: "Hotels", icon: "bed.double"),
        ]),
    ]
    @State private var looseCards: [LooseCard] = []

    var body: some View {
        ZStack {
            Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255)
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    showPhotoPicker = true
                }

            WarpedGridView()
                .ignoresSafeArea()

            if images.isEmpty {
                GlassCard()
            }

            OutputCard()
                .zIndex(1)

            GroupedCardsView(groups: $groups, looseCards: $looseCards)
                .zIndex(2)

            // Floating prompt circle / bar — follows mouse, full screen overlay
            AnimatedPromptBar(isExpanded: $promptExpanded) { text, position in
                let newCard = LooseCard(
                    id: UUID().uuidString,
                    title: text,
                    icon: randomIcons.randomElement() ?? "doc.text",
                    position: position
                )
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    looseCards.append(newCard)
                }
            }
            .zIndex(20)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItems, matching: .images)
        .onChange(of: selectedItems) {
            Task { await loadImages() }
        }
    }

    private func loadImages() async {
        var newImages: [NSImage] = []
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let nsImage = NSImage(data: data) {
                newImages.append(nsImage)
            }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            images = newImages
        }
    }
}

// MARK: - Warped Grid

struct WarpedGridView: View {
    private let lineColor = Color(red: 222 / 255, green: 115 / 255, blue: 86 / 255).opacity(0.7)
    private let bgColor = Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255)

    private let lineCount: Int = 5
    private let lineWidth: CGFloat = 0.5
    private let margin: CGFloat = 0.3
    private let warpStrength: CGFloat = 0.8
    private let segments: Int = 120

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let halfW = w / 2
            let halfH = h / 2
            let k = warpStrength

            context.fill(Path(CGRect(origin: .zero, size: CGSize(width: w, height: h))), with: .color(bgColor))

            func warp(_ p: CGPoint) -> CGPoint {
                let nx = (p.x - cx) / halfW
                let ny = (p.y - cy) / halfH
                let fx = 1.0 + k * ny * ny
                let fy = 1.0 + k * nx * nx
                return CGPoint(x: cx + nx * fx * halfW, y: cy + ny * fy * halfH)
            }

            let gridHalf = cy * (1 - margin)
            let spacing = gridHalf / CGFloat(lineCount)
            let vLineCount = Int(cx / spacing)

            for i in -lineCount...lineCount {
                let y = cy + CGFloat(i) * spacing
                var path = Path()
                for s in 0...segments {
                    let u = CGFloat(s) / CGFloat(segments)
                    let x = u * w
                    let wp = warp(CGPoint(x: x, y: y))
                    if s == 0 { path.move(to: wp) } else { path.addLine(to: wp) }
                }
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }

            let topY = cy - gridHalf
            let bottomY = cy + gridHalf

            for i in -vLineCount...vLineCount {
                let x = cx + CGFloat(i) * spacing
                var path = Path()
                for s in 0...segments {
                    let u = CGFloat(s) / CGFloat(segments)
                    let y = topY + u * (bottomY - topY)
                    let wp = warp(CGPoint(x: x, y: y))
                    if s == 0 { path.move(to: wp) } else { path.addLine(to: wp) }
                }
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
        .clipped()
        .drawingGroup()
    }
}

// MARK: - Data Models

struct CardData: Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct CardGroup: Identifiable {
    let id: String
    let title: String
    let color: Color
    var cards: [CardData]
}

struct LooseCard: Identifiable {
    let id: String
    let title: String
    let icon: String
    var position: CGPoint
}

private let randomIcons = [
    "doc.text", "lightbulb", "star", "bookmark", "tag",
    "heart", "bolt", "flame", "globe", "music.note",
    "camera", "pencil", "paperplane", "gift", "chart.bar"
]

// MARK: - Grouped Cards View

struct GroupedCardsView: View {
    @Binding var groups: [CardGroup]
    @Binding var looseCards: [LooseCard]
    private let clusterRadius: CGFloat = 80
    private let groupSpreadRadius: CGFloat = 260

    @State private var selectedCardId: String? = nil
    @State private var savedOffsets: [String: CGSize] = [:]
    @State private var activeDrag: [String: CGSize] = [:]
    @State private var looseCardDrags: [String: CGSize] = [:]
    @State private var detailCard: CardData? = nil
    @State private var detailGroup: CardGroup? = nil
    @State private var glowingGroupId: String? = nil

    private func fibonacciPos(index: Int, count: Int, centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> CGPoint {
        let goldenAngle = CGFloat.pi * (3.0 - sqrt(5.0))
        let t = count <= 1 ? 0.0 : CGFloat(index) / CGFloat(count - 1)
        let phi = CGFloat(index) * goldenAngle
        let cosTheta = 1.0 - 2.0 * t
        let sinTheta = sqrt(max(0, 1.0 - cosTheta * cosTheta))
        return CGPoint(
            x: centerX + sinTheta * cos(phi) * radius,
            y: centerY + sinTheta * sin(phi) * radius
        )
    }

    private func groupCenter(_ gi: Int, cx: CGFloat, cy: CGFloat) -> CGPoint {
        let n = groups.count
        let angle = (CGFloat.pi * 2 / CGFloat(n)) * CGFloat(gi) - .pi / 2
        return CGPoint(x: cx + cos(angle) * groupSpreadRadius,
                       y: cy + sin(angle) * groupSpreadRadius)
    }

    private func cardPosition(groupIndex gi: Int, cardIndex ci: Int, cx: CGFloat, cy: CGFloat) -> CGPoint {
        let gc = groupCenter(gi, cx: cx, cy: cy)
        let count = groups[gi].cards.count
        let base = fibonacciPos(index: ci, count: count, centerX: gc.x, centerY: gc.y, radius: clusterRadius)
        let cardId = groups[gi].cards[ci].id
        let saved = savedOffsets[cardId] ?? .zero
        let drag = activeDrag[cardId] ?? .zero
        return CGPoint(x: base.x + saved.width + drag.width,
                       y: base.y + saved.height + drag.height)
    }

    private func groupCircleInfo(groupIndex gi: Int, cx: CGFloat, cy: CGFloat) -> (center: CGPoint, radius: CGFloat)? {
        let group = groups[gi]
        let n = group.cards.count
        guard n > 0 else { return nil }
        var positions: [CGPoint] = []
        for ci in 0..<n {
            positions.append(cardPosition(groupIndex: gi, cardIndex: ci, cx: cx, cy: cy))
        }
        let avgX = positions.map(\.x).reduce(0, +) / CGFloat(n)
        let avgY = positions.map(\.y).reduce(0, +) / CGFloat(n)
        let maxDist = positions.map { hypot($0.x - avgX, $0.y - avgY) }.max() ?? 0
        return (CGPoint(x: avgX, y: avgY), maxDist + 70)
    }

    private func groupContaining(point: CGPoint, cx: CGFloat, cy: CGFloat) -> Int? {
        for gi in 0..<groups.count {
            if let info = groupCircleInfo(groupIndex: gi, cx: cx, cy: cy) {
                if hypot(point.x - info.center.x, point.y - info.center.y) <= info.radius {
                    return gi
                }
            }
        }
        return nil
    }

    private func addLooseCardToGroup(looseCard: LooseCard, groupIndex gi: Int) {
        let newCard = CardData(id: looseCard.id, title: looseCard.title, icon: looseCard.icon)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            groups[gi].cards.append(newCard)
            looseCards.removeAll { $0.id == looseCard.id }
            looseCardDrags.removeValue(forKey: looseCard.id)
        }
        glowingGroupId = groups[gi].id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                glowingGroupId = nil
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                // Canvas: group circles + connection lines + midpoint dots
                Canvas { context, _ in
                    for gi in 0..<groups.count {
                        let group = groups[gi]
                        let n = group.cards.count

                        var positions: [CGPoint] = []
                        for ci in 0..<n {
                            positions.append(cardPosition(groupIndex: gi, cardIndex: ci, cx: cx, cy: cy))
                        }

                        // Group encompassing circle
                        if let info = groupCircleInfo(groupIndex: gi, cx: cx, cy: cy) {
                            let circleR = info.radius
                            let circleRect = CGRect(x: info.center.x - circleR, y: info.center.y - circleR, width: circleR * 2, height: circleR * 2)
                            let circlePath = Path(ellipseIn: circleRect)

                            let isGlowing = glowingGroupId == group.id
                            let fillOpacity: CGFloat = isGlowing ? 0.15 : 0.05
                            let strokeOpacity: CGFloat = isGlowing ? 0.6 : 0.3

                            context.fill(circlePath, with: .color(group.color.opacity(fillOpacity)))
                            let dashed = circlePath.strokedPath(StrokeStyle(lineWidth: isGlowing ? 1.5 : 1, dash: [6, 4]))
                            context.fill(dashed, with: .color(group.color.opacity(strokeOpacity)))
                        }

                        // Intra-group connection lines
                        if n >= 2 {
                            for ci in 0..<(n - 1) {
                                let from = positions[ci]
                                let to = positions[ci + 1]

                                var linePath = Path()
                                linePath.move(to: from)
                                linePath.addLine(to: to)
                                context.stroke(linePath, with: .color(group.color.opacity(0.2)), lineWidth: 0.5)

                                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                                let dotRect = CGRect(x: mid.x - 2, y: mid.y - 2, width: 4, height: 4)
                                context.fill(Path(ellipseIn: dotRect), with: .color(group.color))
                            }

                            if n >= 3 {
                                let from = positions[n - 1]
                                let to = positions[0]
                                var linePath = Path()
                                linePath.move(to: from)
                                linePath.addLine(to: to)
                                context.stroke(linePath, with: .color(group.color.opacity(0.2)), lineWidth: 0.5)

                                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                                let dotRect = CGRect(x: mid.x - 2, y: mid.y - 2, width: 4, height: 4)
                                context.fill(Path(ellipseIn: dotRect), with: .color(group.color))
                            }
                        }
                    }
                }

                // Cards
                ForEach(0..<groups.count, id: \.self) { gi in
                    let group = groups[gi]
                    ForEach(0..<group.cards.count, id: \.self) { ci in
                        let card = group.cards[ci]
                        let pos = cardPosition(groupIndex: gi, cardIndex: ci, cx: cx, cy: cy)
                        let isSelected = selectedCardId == card.id
                        let hasFocus = selectedCardId != nil

                        GroupCard(card: card, groupColor: group.color)
                            .scaleEffect(isSelected ? 1.15 : (hasFocus ? 0.9 : 1.0))
                            .opacity(isSelected ? 1.0 : (hasFocus ? 0.4 : 1.0))
                            .shadow(color: isSelected ? .black.opacity(0.2) : .clear, radius: 16, y: 8)
                            .zIndex(isSelected ? 10 : 0)
                            .position(x: pos.x, y: pos.y)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        selectedCardId = card.id
                                        activeDrag[card.id] = value.translation
                                    }
                                    .onEnded { value in
                                        let prev = savedOffsets[card.id] ?? .zero
                                        savedOffsets[card.id] = CGSize(
                                            width: prev.width + value.translation.width,
                                            height: prev.height + value.translation.height
                                        )
                                        activeDrag[card.id] = .zero
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedCardId = nil
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded {
                                        withAnimation(.spring(response: 0.35)) {
                                            selectedCardId = card.id
                                            detailCard = card
                                            detailGroup = group
                                            glowingGroupId = group.id
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            withAnimation(.easeOut(duration: 0.6)) {
                                                glowingGroupId = nil
                                            }
                                        }
                                    }
                            )
                            .animation(.spring(response: 0.35), value: selectedCardId)
                    }
                }

                // Loose (ungrouped) cards
                ForEach(looseCards) { looseCard in
                    let drag = looseCardDrags[looseCard.id] ?? .zero
                    let currentPos = CGPoint(
                        x: looseCard.position.x + drag.width,
                        y: looseCard.position.y + drag.height
                    )

                    LooseCardView(title: looseCard.title, icon: looseCard.icon)
                        .position(currentPos)
                        .zIndex(5)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    looseCardDrags[looseCard.id] = value.translation
                                    let hoverPoint = CGPoint(
                                        x: looseCard.position.x + value.translation.width,
                                        y: looseCard.position.y + value.translation.height
                                    )
                                    if let gi = groupContaining(point: hoverPoint, cx: cx, cy: cy) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            glowingGroupId = groups[gi].id
                                        }
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            glowingGroupId = nil
                                        }
                                    }
                                }
                                .onEnded { value in
                                    let dropPoint = CGPoint(
                                        x: looseCard.position.x + value.translation.width,
                                        y: looseCard.position.y + value.translation.height
                                    )
                                    looseCardDrags[looseCard.id] = .zero

                                    if let gi = groupContaining(point: dropPoint, cx: cx, cy: cy) {
                                        addLooseCardToGroup(looseCard: looseCard, groupIndex: gi)
                                    } else {
                                        if let idx = looseCards.firstIndex(where: { $0.id == looseCard.id }) {
                                            looseCards[idx].position = dropPoint
                                        }
                                    }

                                    withAnimation(.easeOut(duration: 0.3)) {
                                        glowingGroupId = nil
                                    }
                                }
                        )
                }

                // Card Detail Overlay
                if let card = detailCard, let group = detailGroup {
                    // Dimmed backdrop
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                detailCard = nil
                                detailGroup = nil
                                selectedCardId = nil
                            }
                        }
                        .zIndex(50)

                    CardDetailView(card: card, group: group) {
                        withAnimation(.spring(response: 0.3)) {
                            detailCard = nil
                            detailGroup = nil
                            selectedCardId = nil
                        }
                    }
                    .zIndex(51)
                }
            }
        }
    }
}

// MARK: - Group Card

struct GroupCard: View {
    let card: CardData
    let groupColor: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: card.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(groupColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(groupColor.opacity(0.1))
                )

            Text(card.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .frame(width: 90, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        )
    }
}

// MARK: - Loose Card View

struct LooseCardView: View {
    let title: String
    let icon: String
    private let looseColor = Color(red: 150/255, green: 150/255, blue: 150/255)

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(looseColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(looseColor.opacity(0.1))
                )

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 90, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                        .foregroundStyle(looseColor.opacity(0.4))
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        )
    }
}

// MARK: - Card Detail View

struct CardDetailView: View {
    let card: CardData
    let group: CardGroup
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: badge + close
            HStack {
                Text(group.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(group.color))

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 18)

            // Title
            Text(card.title)
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(.primary)
            Spacer().frame(height: 14)

            // Body placeholder
            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Spacer().frame(height: 20)

            // Connections section
            VStack(alignment: .leading, spacing: 8) {
                Text("Connections")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                ForEach(group.cards.filter { $0.id != card.id }) { sibling in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(group.color)
                            .frame(width: 6, height: 6)

                        Image(systemName: sibling.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(group.color)

                        Text(sibling.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .transition(
            .scale(scale: 0.9, anchor: .center)
            .combined(with: .opacity)
        )
    }
}

// MARK: - Output Card

struct OutputCard: View {
    private let cardWidth: CGFloat = 260
    private let cornerRadius: CGFloat = 16
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("travel")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.2))
                    )

                Text("Here's what I see in your photos")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .overlay(.white.opacity(0.15))
                .padding(.horizontal, 16)

            // Body
            VStack(alignment: .leading, spacing: 14) {
                Text("Weekend Getaway")
                    .font(.custom("DM Serif Display", size: 20))
                    .foregroundStyle(.white)

                OutputSection(heading: "Places", items: ["Coastal cliffs at sunset", "Old town market square"])
                OutputSection(heading: "Mood", items: ["Warm golden light", "Relaxed, candid moments"])
                OutputSection(heading: "Story", items: ["A weekend road-trip south along the coast"])
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)

            // Footer
            Text("Want me to turn this into a travel log?")
                .font(.system(size: 12, weight: .regular))
                .italic()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 0,
                            bottomLeading: cornerRadius,
                            bottomTrailing: cornerRadius,
                            topTrailing: 0
                        )
                    )
                    .fill(.white.opacity(0.15))
                )
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(accentColor)
                .shadow(color: accentColor.opacity(0.35), radius: 16, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .transition(
            .scale(scale: 0.9)
            .combined(with: .opacity)
        )
    }
}

struct OutputSection: View {
    let heading: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.8)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)

                    Text(item)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
}

// MARK: - Animated Prompt Bar

struct AnimatedPromptBar: View {
    @Binding var isExpanded: Bool
    var onSubmit: (String, CGPoint) -> Void
    @State private var phase: PromptPhase = .circle
    @State private var mousePos: CGPoint = .zero
    @State private var anchorPos: CGPoint = .zero  // where the bar opens
    @State private var rollOffset: CGFloat = 0
    @State private var rollRotation: Double = 0
    @State private var barWidth: CGFloat = 40
    @State private var promptText: String = ""
    @FocusState private var isFocused: Bool

    private let circleSize: CGFloat = 40
    private let expandedWidth: CGFloat = 400
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    enum PromptPhase {
        case circle
        case rolling
        case expanding
        case expanded
    }

    var body: some View {
        GeometryReader { geo in
            // Where the shape should be
            let posX: CGFloat = phase == .circle ? mousePos.x : anchorPos.x + rollOffset
            let posY: CGFloat = phase == .circle ? mousePos.y : anchorPos.y

            HStack(spacing: 0) {
                if phase == .expanded {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))

                        TextField("Ask CanvasAi anything…", text: $promptText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .focused($isFocused)
                            .onSubmit { submitPrompt() }

                        Button { submitPrompt() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(
                                    promptText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 0.8
                                ))
                        }
                        .buttonStyle(.plain)
                        .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
                }
            }
            .frame(width: barWidth, height: circleSize)
            .background(
                Capsule()
                    .fill(accentColor)
                    .shadow(color: accentColor.opacity(0.3), radius: 12, y: 4)
            )
            .clipShape(Capsule())
            .rotationEffect(.degrees(rollRotation))
            .position(x: posX, y: posY)
            .animation(phase == .circle ? .smooth(duration: 0.15) : nil, value: mousePos)
        }
        .allowsHitTesting(phase == .expanded)
        .background(
            MouseTrackingView(
                onMouseMove: { point in
                    if phase == .circle { mousePos = point }
                },
                onRightClick: {
                    if phase == .circle {
                        expandAnimation()
                    } else if phase == .expanded || phase == .expanding {
                        collapseAnimation()
                    }
                }
            )
        )
    }

    private func submitPrompt() {
        let trimmed = promptText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let spawnPosition = CGPoint(x: anchorPos.x + rollOffset, y: anchorPos.y - 80)
        onSubmit(trimmed, spawnPosition)
        collapseAnimation()
    }

    private func expandAnimation() {
        // Lock the anchor at current mouse position
        anchorPos = CGPoint(x: mousePos.x - 80, y: mousePos.y)
        isExpanded = true
        phase = .rolling

        // Phase 1: Roll to the right from click spot
        withAnimation(.easeIn(duration: 0.45)) {
            rollOffset = 80
            rollRotation = 360
        }

        // Phase 2: Stop rolling, expand width in place
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            phase = .expanding
            rollRotation = 0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                rollOffset = 0
                barWidth = expandedWidth
            }
        }

        // Phase 3: Show text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            phase = .expanded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFocused = true
            }
        }
    }

    private func collapseAnimation() {
        isFocused = false
        promptText = ""

        // Shrink bar back to circle
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            barWidth = circleSize
            phase = .circle
            isExpanded = false
        }

        // Reset offsets so it picks up mouse again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            rollOffset = 0
            rollRotation = 0
        }
    }
}

// MARK: - Glass Card

struct GlassCard: View {
    private let cardWidth: CGFloat = 340
    private let cardHeight: CGFloat = 400
    private let cornerRadius: CGFloat = 20
    private let thickness: CGFloat = 6
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(accentColor.opacity(0.15))
                .frame(width: cardWidth, height: cardHeight)
                .offset(y: thickness)

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.85))

                Text("CanvasAi")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)

                Text("Drop an image to begin")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(accentColor.opacity(0.6))
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 204/255, green: 85/255, blue: 0/255).opacity(0.6))
            )
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        }
        //.shadow(color: accentColor.opacity(0.35), radius: 16, y: 8)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Mouse Tracking View

struct MouseTrackingView: NSViewRepresentable {
    let onMouseMove: (CGPoint) -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onMouseMove = onMouseMove
        view.onRightClick = onRightClick
        view.setupMonitor()
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMouseMove = onMouseMove
        nsView.onRightClick = onRightClick
    }

    class TrackingNSView: NSView {
        var onMouseMove: ((CGPoint) -> Void)?
        var onRightClick: (() -> Void)?
        private var monitor: Any?

        func setupMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                self?.onRightClick?()
                return nil
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
            onMouseMove?(flipped)
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        // Transparent to hit-testing so clicks/drags pass through
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 800)
}
