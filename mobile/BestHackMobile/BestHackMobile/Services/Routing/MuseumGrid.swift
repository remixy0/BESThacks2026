import Foundation
import simd

/// The backend's walking map, `field-museum-main-level.grid.json`: the same file the server routes on, bundled so
/// the phone can plan routes by itself when the server can't (the failsafe).
///
/// - 0.2 m cells, `cells[row][column]`, only `1` is walkable (the map already keeps 1 m from obstacles).
/// - Map x = model X, map y = model Z: exactly the app's floor point, so no conversion anywhere.
/// - `pointsOfInterest[].approach` is where to stand at each exhibit (its `sourceId` is our exhibit key);
///   `approach: null` = can't be reached (closed or staff-only room).
///
/// Keep Resources/Museum/field-museum-main-level.grid.json identical to the backend's copy
/// (backend/java-backend/src/main/resources/maps/) whenever the map changes.
nonisolated final class MuseumGrid: Sendable {
    /// Loaded on first use (≈0.8 MB of JSON). Nil if the file is missing or unreadable.
    static let shared: MuseumGrid? = load()

    nonisolated struct Rect: Sendable, Equatable {
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float
    }

    let width: Int
    let height: Int
    let cellSize: Float
    let origin: SIMD2<Float>
    /// Exhibit key → where to stand to see it.
    let approaches: [String: SIMD2<Float>]
    /// Exhibits the map says can't be reached.
    let unreachable: Set<String>
    /// Where the entrances are (the ways out during an alarm).
    let exits: [SIMD2<Float>]
    private let walkable: [Bool]

    private init(width: Int, height: Int, cellSize: Float, origin: SIMD2<Float>, walkable: [Bool],
                 approaches: [String: SIMD2<Float>], unreachable: Set<String>, exits: [SIMD2<Float>]) {
        self.width = width
        self.height = height
        self.cellSize = cellSize
        self.origin = origin
        self.walkable = walkable
        self.approaches = approaches
        self.unreachable = unreachable
        self.exits = exits
    }

    // MARK: - Routing

    /// A walking route from `start` to `end`, smoothed into straight stretches: [start, corners…, end].
    /// `zones` (areas closed by the staff, from the server's last `policy`) are avoided, grown by 0.3 m like the
    /// server does. Nil when there's no way through.
    func route(from start: SIMD2<Float>, to end: SIMD2<Float>, avoiding zones: [Rect] = []) -> [SIMD2<Float>]? {
        let open = zones.isEmpty ? walkable : carve(zones)
        guard let from = nearestOpen(to: start, in: open, within: 4),
              let to = nearestOpen(to: end, in: open, within: 3) else { return nil }
        guard let cells = search(from: from, to: to, in: open) else { return nil }

        // Greedy string-pulling: keep a corner only where the straight line would cut through a wall.
        let centers = cells.map(center(of:))
        var points = [start]
        var anchor = centers[0]
        for index in 1..<max(centers.count, 1) where !clearLine(from: anchor, to: centers[index], in: open) {
            anchor = centers[index - 1]
            points.append(anchor)
        }
        points.append(end)
        return points
    }

    /// True when the cell under `point` is walkable.
    func isWalkable(_ point: SIMD2<Float>) -> Bool {
        guard let index = index(of: point) else { return false }
        return walkable[index]
    }

    // MARK: - A*

    /// 8 neighbours (no cutting past corners), octile distance. Returns cell indices from `start` to `goal`.
    private func search(from start: Int, to goal: Int, in open: [Bool]) -> [Int]? {
        let count = width * height
        var cost = [Float](repeating: .infinity, count: count)
        var parent = [Int32](repeating: -1, count: count)
        var closed = [Bool](repeating: false, count: count)
        var heap = MinHeap()
        let goalX = goal % width
        let goalY = goal / width
        let diagonal: Float = 1.41421356

        func estimate(_ index: Int) -> Float {
            let dx = Float(abs(index % width - goalX))
            let dy = Float(abs(index / width - goalY))
            return dx + dy + (diagonal - 2) * min(dx, dy)
        }

        cost[start] = 0
        heap.push(estimate(start), start)
        let steps: [(Int, Int, Float)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
                                          (1, 1, diagonal), (1, -1, diagonal), (-1, 1, diagonal), (-1, -1, diagonal)]
        var found = false
        while let current = heap.pop() {
            if closed[current] { continue }
            closed[current] = true
            if current == goal {
                found = true
                break
            }
            let x = current % width
            let y = current / width
            for (dx, dy, step) in steps {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let next = ny * width + nx
                guard open[next], !closed[next] else { continue }
                if dx != 0, dy != 0, !(open[y * width + nx] && open[ny * width + x]) { continue }
                let newCost = cost[current] + step
                if newCost < cost[next] {
                    cost[next] = newCost
                    parent[next] = Int32(current)
                    heap.push(newCost + estimate(next), next)
                }
            }
        }
        guard found else { return nil }
        var path: [Int] = []
        var index = goal
        while index != -1 {
            path.append(index)
            index = Int(parent[index])
        }
        return path.reversed()
    }

    // MARK: - Cells

    private func index(of point: SIMD2<Float>) -> Int? {
        let column = Int(((point.x - origin.x) / cellSize).rounded(.down))
        let row = Int(((point.y - origin.y) / cellSize).rounded(.down))
        guard column >= 0, row >= 0, column < width, row < height else { return nil }
        return row * width + column
    }

    private func center(of index: Int) -> SIMD2<Float> {
        SIMD2(origin.x + (Float(index % width) + 0.5) * cellSize,
              origin.y + (Float(index / width) + 0.5) * cellSize)
    }

    /// The walkable cell closest to `point`, searching outwards up to `metres` (beacon positions can land in a wall).
    private func nearestOpen(to point: SIMD2<Float>, in open: [Bool], within metres: Float) -> Int? {
        let column = Int(((point.x - origin.x) / cellSize).rounded(.down))
        let row = Int(((point.y - origin.y) / cellSize).rounded(.down))
        let reach = Int(metres / cellSize)
        var best: Int?
        var bestDistance = Float.infinity
        for radius in 0...reach {
            if best != nil, Float(radius) * cellSize > bestDistance { break }
            for dy in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dy)) == radius {
                    let x = column + dx
                    let y = row + dy
                    guard x >= 0, y >= 0, x < width, y < height else { continue }
                    let candidate = y * width + x
                    guard open[candidate] else { continue }
                    let distance = simd_distance(center(of: candidate), point)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = candidate
                    }
                }
            }
        }
        return best
    }

    /// True when every cell along the straight line is walkable (checked every half cell).
    private func clearLine(from a: SIMD2<Float>, to b: SIMD2<Float>, in open: [Bool]) -> Bool {
        let length = simd_distance(a, b)
        let steps = max(1, Int(length / (cellSize * 0.5)))
        for step in 0...steps {
            let point = a + (b - a) * (Float(step) / Float(steps))
            guard let index = index(of: point), open[index] else { return false }
        }
        return true
    }

    /// The walkable map with the closed zones (plus 0.3 m) blocked out.
    private func carve(_ zones: [Rect]) -> [Bool] {
        var open = walkable
        let margin: Float = 0.3
        for zone in zones {
            let minColumn = max(0, Int(((zone.minX - margin - origin.x) / cellSize).rounded(.down)))
            let maxColumn = min(width - 1, Int(((zone.maxX + margin - origin.x) / cellSize).rounded(.down)))
            let minRow = max(0, Int(((zone.minY - margin - origin.y) / cellSize).rounded(.down)))
            let maxRow = min(height - 1, Int(((zone.maxY + margin - origin.y) / cellSize).rounded(.down)))
            guard minColumn <= maxColumn, minRow <= maxRow else { continue }
            for row in minRow...maxRow {
                for column in minColumn...maxColumn {
                    open[row * width + column] = false
                }
            }
        }
        return open
    }

    // MARK: - Loading

    private static func load() -> MuseumGrid? {
        guard let url = MuseumAssets.url(named: "field-museum-main-level.grid", extension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let width = json["width"] as? Int, let height = json["height"] as? Int,
              let cellSize = (json["cellSizeM"] as? NSNumber)?.floatValue,
              let origin = json["origin"] as? [String: Any],
              let originX = (origin["x"] as? NSNumber)?.floatValue, let originY = (origin["y"] as? NSNumber)?.floatValue,
              let rows = json["cells"] as? [String], rows.count == height else {
            print("[Grid] field-museum-main-level.grid.json is missing or unreadable: local routes will be straight lines")
            return nil
        }
        let navigation = json["navigation"] as? [String: Any]
        let walkableCode = ((navigation?["walkableCode"] as? String)?.utf8.first) ?? UInt8(ascii: "1")
        var walkable = [Bool](repeating: false, count: width * height)
        for (row, line) in rows.enumerated() {
            var column = 0
            for byte in line.utf8 where column < width {
                if byte == walkableCode { walkable[row * width + column] = true }
                column += 1
            }
        }

        var approaches: [String: SIMD2<Float>] = [:]
        var unreachable: Set<String> = []
        var exits: [SIMD2<Float>] = []
        for poi in json["pointsOfInterest"] as? [[String: Any]] ?? [] {
            let key = poi["sourceId"] as? String ?? poi["id"] as? String ?? ""
            let kind = poi["kind"] as? String
            if let approach = poi["approach"] as? [String: Any],
               let x = (approach["x"] as? NSNumber)?.floatValue, let y = (approach["y"] as? NSNumber)?.floatValue {
                let point = SIMD2(x, y)
                if kind == "entrance" { exits.append(point) }
                if approaches[key] == nil { approaches[key] = point }
            } else if kind == "exhibit" {
                unreachable.insert(key)
            }
        }
        print("[Grid] \(width)×\(height) cells, \(approaches.count) places, \(exits.count) exits")
        return MuseumGrid(width: width, height: height, cellSize: cellSize, origin: SIMD2(originX, originY),
                          walkable: walkable, approaches: approaches, unreachable: unreachable, exits: exits)
    }
}

/// A small binary min-heap of (priority, cell) for A*.
nonisolated private struct MinHeap {
    private var items: [(priority: Float, value: Int)] = []

    mutating func push(_ priority: Float, _ value: Int) {
        items.append((priority, value))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].priority < items[parent].priority else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Int? {
        guard !items.isEmpty else { return nil }
        let top = items[0].value
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var parent = 0
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var smallest = parent
                if left < items.count, items[left].priority < items[smallest].priority { smallest = left }
                if right < items.count, items[right].priority < items[smallest].priority { smallest = right }
                guard smallest != parent else { break }
                items.swapAt(parent, smallest)
                parent = smallest
            }
        }
        return top
    }
}
