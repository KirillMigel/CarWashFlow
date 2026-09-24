import Foundation
import simd

final class ClothSimulation {

    let cols: Int
    let rows: Int
    let width: Float
    let height: Float
    let count: Int

    let pos: UnsafeMutablePointer<Float>
    let prev: UnsafeMutablePointer<Float>
    let flat: UnsafeMutablePointer<Float>
    let memory: UnsafeMutablePointer<Float>
    let normal: UnsafeMutablePointer<Float>
    let uv: UnsafeMutablePointer<Float>
    let indices: [UInt32]

    private let constraintCount: Int
    private let ca: UnsafeMutablePointer<Int32>
    private let cb: UnsafeMutablePointer<Int32>
    private let cl: UnsafeMutablePointer<Float>
    private let cw: UnsafeMutablePointer<Float>
    private let cf: UnsafeMutablePointer<Float>

    private let pinned: UnsafeMutablePointer<UInt8>
    private let pins: [Int32]
    private let neighbours: UnsafeMutablePointer<Int32>
    private let fix: UnsafeMutablePointer<Float>

    private let gravity: Float
    private let restSpring: Float
    private let relax: Float
    private let wind: Float
    private let damping: Float
    private let iterations: Int
    private let grabRadius: Float
    private let grabLift: Float
    private let grabStrength: Float

    private let dt: Float = 1.0 / 120.0
    private let spacing: Float
    private let vmax: Float
    private let kink: Float
    private let ktarget: Float

    private(set) var time: Float = 0
    private var settling = false
    private var stuckT: Float = 0
    private var heal: Float = 0
    private var kinkN = 0
    private var speed: Float = 0
    private var offRest: Float = 0
    private var frameParity = 0
    private var pendingSettle = 0

    var needsSettle: Bool { pendingSettle > 0 }

    private var grabN = 0
    private let grabIdx: UnsafeMutablePointer<Int32>
    private let grabW: UnsafeMutablePointer<Float>
    private let grabOff: UnsafeMutablePointer<Float>
    private var grabTarget = SIMD3<Float>(repeating: 0)
    private var grabLiftVec = SIMD3<Float>(repeating: 0)

    var onStep: ((ClothSimulation, Float) -> Void)?

    var isGrabbing: Bool { grabN > 0 }

    init(physics p: ClothPhysics) {
        cols = max(2, p.cols)
        rows = max(2, p.rows)
        width = p.width
        height = p.height
        count = cols * rows

        gravity = p.gravity
        restSpring = p.restSpring
        relax = p.relax
        wind = p.wind * p.windScale
        damping = p.damping
        iterations = max(1, p.iterations)
        grabRadius = p.grabRadius
        grabLift = p.grabLift
        grabStrength = p.grabStrength

        let n3 = count * 3
        pos = .allocate(capacity: n3)
        prev = .allocate(capacity: n3)
        flat = .allocate(capacity: n3)
        memory = .allocate(capacity: n3)
        normal = .allocate(capacity: n3)
        fix = .allocate(capacity: n3)
        uv = .allocate(capacity: count * 2)
        pinned = .allocate(capacity: count)
        neighbours = .allocate(capacity: count * 4)
        grabIdx = .allocate(capacity: count)
        grabW = .allocate(capacity: count)
        grabOff = .allocate(capacity: n3)
        normal.initialize(repeating: 0, count: n3)
        fix.initialize(repeating: 0, count: n3)
        pinned.initialize(repeating: 0, count: count)

        let segW = width / Float(cols - 1)
        let segH = height / Float(rows - 1)
        for j in 0..<rows {
            for i in 0..<cols {
                let k = j * cols + i
                flat[3 * k] = Float(i) * segW - width * 0.5
                flat[3 * k + 1] = height * 0.5 - Float(j) * segH
                flat[3 * k + 2] = 0
                uv[2 * k] = Float(i) / Float(cols - 1)
                uv[2 * k + 1] = 1 - Float(j) / Float(rows - 1)
            }
        }
        pos.update(from: flat, count: n3)
        prev.update(from: flat, count: n3)
        memory.update(from: flat, count: n3)

        var idx: [UInt32] = []
        idx.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for j in 0..<(rows - 1) {
            for i in 0..<(cols - 1) {
                let a = UInt32(i + cols * j)
                let b = UInt32(i + cols * (j + 1))
                let c = UInt32((i + 1) + cols * (j + 1))
                let d = UInt32((i + 1) + cols * j)
                idx.append(contentsOf: [a, b, d, b, c, d])
            }
        }
        indices = idx

        var cons: [(Int, Int, Float, Float, Float)] = []
        cons.reserveCapacity(count * 8)
        let flatRef = flat
        func add(_ a: Int, _ b: Int, _ weight: Float, _ floor: Float = 0.78) {
            let a3 = 3 * a, b3 = 3 * b
            let dx = flatRef[b3] - flatRef[a3]
            let dy = flatRef[b3 + 1] - flatRef[a3 + 1]
            let dz = flatRef[b3 + 2] - flatRef[a3 + 2]
            cons.append((a, b, (dx * dx + dy * dy + dz * dz).squareRoot(), weight, floor))
        }
        let cc = cols
        let id: (Int, Int) -> Int = { i, j in j * cc + i }
        let shear = p.shear, bend = p.bend
        for j in 0..<rows {
            for i in 0..<cols {
                if i + 1 < cols { add(id(i, j), id(i + 1, j), 1) }
                if j + 1 < rows { add(id(i, j), id(i, j + 1), 1) }
                if i + 1 < cols && j + 1 < rows {
                    add(id(i, j), id(i + 1, j + 1), shear)
                    add(id(i + 1, j), id(i, j + 1), shear)
                }
                if i + 2 < cols { add(id(i, j), id(i + 2, j), bend, 0.88) }
                if j + 2 < rows { add(id(i, j), id(i, j + 2), bend, 0.88) }
                if i + 2 < cols && j + 2 < rows {
                    add(id(i, j), id(i + 2, j + 2), bend * 0.8, 0.88)
                    add(id(i + 2, j), id(i, j + 2), bend * 0.8, 0.88)
                }
            }
        }
        constraintCount = cons.count
        ca = .allocate(capacity: constraintCount)
        cb = .allocate(capacity: constraintCount)
        cl = .allocate(capacity: constraintCount)
        cw = .allocate(capacity: constraintCount)
        cf = .allocate(capacity: constraintCount)
        for (k, c) in cons.enumerated() {
            ca[k] = Int32(3 * c.0); cb[k] = Int32(3 * c.1)
            cl[k] = c.2; cw[k] = c.3; cf[k] = c.4
        }

        var pinList: [Int] = []
        let bottom = rows - 1
        switch p.pins {
        case .none: break
        case .top: for i in 0..<cols { pinList.append(id(i, 0)) }
        case .topCorners: pinList += [id(0, 0), id(cols - 1, 0)]
        case .left: for j in 0..<rows { pinList.append(id(0, j)) }
        case .corners: pinList += [id(0, 0), id(cols - 1, 0), id(0, bottom), id(cols - 1, bottom)]
        case .custom(let list): for c in list { pinList.append(id(min(max(c.x, 0), cols - 1), min(max(c.y, 0), rows - 1))) }
        }
        pins = pinList.map { Int32(3 * $0) }
        for k in pinList { pinned[k] = 1 }

        for j in 0..<rows {
            for i in 0..<cols {
                let b = 4 * id(i, j)
                neighbours[b] = i > 0 ? Int32(id(i - 1, j)) : -1
                neighbours[b + 1] = i < cols - 1 ? Int32(id(i + 1, j)) : -1
                neighbours[b + 2] = j > 0 ? Int32(id(i, j - 1)) : -1
                neighbours[b + 3] = j < rows - 1 ? Int32(id(i, j + 1)) : -1
            }
        }

        spacing = min(width / Float(cols - 1), height / Float(rows - 1))
        vmax = spacing * 0.45
        kink = spacing * 0.5
        ktarget = spacing * 0.22

        pendingSettle = max(0, p.settle)
        computeNormals()
    }

    @discardableResult
    func settleSlice(maxSteps: Int) -> Bool {
        guard pendingSettle > 0, maxSteps > 0 else { return false }
        let n = min(maxSteps, pendingSettle)
        settling = true
        for _ in 0..<n { time += dt; step() }
        settling = false
        pendingSettle -= n
        if pendingSettle == 0 {
            let n3 = count * 3
            memory.update(from: pos, count: n3)
            prev.update(from: pos, count: n3)
            time = 0
        }
        return pendingSettle > 0
    }

    deinit {
        pos.deallocate(); prev.deallocate(); flat.deallocate(); memory.deallocate()
        normal.deallocate(); fix.deallocate(); uv.deallocate(); pinned.deallocate()
        neighbours.deallocate(); grabIdx.deallocate(); grabW.deallocate(); grabOff.deallocate()
        ca.deallocate(); cb.deallocate(); cl.deallocate(); cw.deallocate(); cf.deallocate()
    }

    func advance(steps n: Int) {
        while settleSlice(maxSteps: .max) {}
        advanceRaw(steps: n)
        refreshNormals()
    }

    func advanceRaw(steps n: Int) {
        guard n > 0 else { return }
        for _ in 0..<n { time += dt; step() }
    }

    func refreshNormals() { computeNormals() }

    func reset() {
        let n3 = count * 3
        pos.update(from: memory, count: n3)
        prev.update(from: memory, count: n3)
        computeNormals()
    }

    private func step() {
        let a = wind
        var ke: Float = 0, dev: Float = 0

        for k in 0..<count {
            let k3 = 3 * k
            let x = pos[k3], y = pos[k3 + 1], z = pos[k3 + 2]
            let rx = flat[k3], ry = flat[k3 + 1]
            var ax = (memory[k3] - x) * restSpring
            var ay = (memory[k3 + 1] - y) * restSpring + gravity
            var az = (memory[k3 + 2] - z) * restSpring
            if a != 0 {
                az += a * (sin(time * 1.15 + rx * 2 + ry * 0.9) * 0.6 + sin(time * 0.75 + ry * 2.4 - rx * 0.6) * 0.4)
                ax += 0.35 * a * cos(time * 0.9 + ry * 1.7)
                ay += 0.28 * a * sin(time * 0.6 + rx * 1.3 + 2)
            }
            var vx = (x - prev[k3]) * damping
            var vy = (y - prev[k3 + 1]) * damping
            var vz = (z - prev[k3 + 2]) * damping
            vx = min(max(vx, -vmax), vmax)
            vy = min(max(vy, -vmax), vmax)
            vz = min(max(vz, -vmax), vmax)
            ke += vx * vx + vy * vy + vz * vz
            let mx = x - memory[k3], my = y - memory[k3 + 1], mz = z - memory[k3 + 2]
            dev += mx * mx + my * my + mz * mz
            prev[k3] = x; prev[k3 + 1] = y; prev[k3 + 2] = z
            pos[k3] = x + vx + ax * dt * dt
            pos[k3 + 1] = y + vy + ay * dt * dt
            pos[k3 + 2] = z + vz + az * dt * dt
        }

        if !settling {
            speed = (ke / Float(count)).squareRoot()
            offRest = (dev / Float(count)).squareRoot()
        }

        for _ in 0..<iterations {
            for c in 0..<constraintCount {
                let a3 = Int(ca[c]), b3 = Int(cb[c])
                let dx = pos[b3] - pos[a3], dy = pos[b3 + 1] - pos[a3 + 1], dz = pos[b3 + 2] - pos[a3 + 2]
                let d = (dx * dx + dy * dy + dz * dz).squareRoot()
                if d < 1e-6 { continue }
                let l = cl[c], floor = l * cf[c]
                let off = d < floor ? (d - floor) / d * 0.5 : (d - l) / d * 0.5 * cw[c]
                let ox = dx * off, oy = dy * off, oz = dz * off
                pos[a3] += ox; pos[a3 + 1] += oy; pos[a3 + 2] += oz
                pos[b3] -= ox; pos[b3 + 1] -= oy; pos[b3 + 2] -= oz
            }
            if grabN > 0 {
                for g in 0..<grabN {
                    let k3 = Int(grabIdx[g]), s = grabW[g] * grabStrength
                    pos[k3] += (grabTarget.x + grabOff[3 * g] + grabLiftVec.x - pos[k3]) * s
                    pos[k3 + 1] += (grabTarget.y + grabOff[3 * g + 1] + grabLiftVec.y - pos[k3 + 1]) * s
                    pos[k3 + 2] += (grabTarget.z + grabOff[3 * g + 2] + grabLiftVec.z - pos[k3 + 2]) * s
                }
            }
            for p in pins {
                let k3 = Int(p)
                pos[k3] = flat[k3]; pos[k3 + 1] = flat[k3 + 1]; pos[k3 + 2] = flat[k3 + 2]
                prev[k3] = flat[k3]; prev[k3 + 1] = flat[k3 + 1]; prev[k3 + 2] = flat[k3 + 2]
            }
        }

        if !settling { onStep?(self, time) }

        frameParity ^= 1
        if frameParity == 1 {
            unfold()
        } else {
            for c in 0..<constraintCount {
                let a3 = Int(ca[c]), b3 = Int(cb[c]), floor = cl[c] * cf[c]
                let dx = pos[b3] - pos[a3], dy = pos[b3 + 1] - pos[a3 + 1], dz = pos[b3 + 2] - pos[a3 + 2]
                let d2 = dx * dx + dy * dy + dz * dz
                if d2 >= floor * floor || d2 < 1e-12 { continue }
                let d = d2.squareRoot(), off = (d - floor) / d * 0.5
                let ox = dx * off, oy = dy * off, oz = dz * off
                pos[a3] += ox; pos[a3 + 1] += oy; pos[a3 + 2] += oz
                pos[b3] -= ox; pos[b3 + 1] -= oy; pos[b3 + 2] -= oz
            }
            for p in pins {
                let k3 = Int(p)
                pos[k3] = flat[k3]; pos[k3 + 1] = flat[k3 + 1]; pos[k3 + 2] = flat[k3 + 2]
            }
        }

        if !settling {
            let kinked = kinkN > 2
            if grabN == 0 && (kinked || (speed < spacing * 0.05 && offRest > spacing * 1.2)) {
                stuckT += dt
            } else {
                stuckT = max(0, stuckT - dt * 3)
            }
            heal = stuckT > 0.8 ? min(1, (stuckT - 0.8) / 1.2) : 0
        }

        let r = relax + heal * 0.05
        if r != 0 {
            for i in 0..<(3 * count) {
                pos[i] += (memory[i] - pos[i]) * r
                prev[i] += (memory[i] - prev[i]) * r
            }
        }
    }

    private func unfold() {
        var hits = 0
        for k in 0..<count {
            let k3 = 3 * k
            fix[k3] = 0; fix[k3 + 1] = 0; fix[k3 + 2] = 0
            if pinned[k] != 0 { continue }
            let b = 4 * k
            var sx: Float = 0, sy: Float = 0, sz: Float = 0, n = 0
            for q in 0..<4 {
                let nb = neighbours[b + q]
                if nb < 0 { continue }
                let n3 = 3 * Int(nb)
                sx += pos[n3]; sy += pos[n3 + 1]; sz += pos[n3 + 2]; n += 1
            }
            if n < 3 { continue }
            let fn = Float(n)
            let dx = pos[k3] - sx / fn, dy = pos[k3 + 1] - sy / fn, dz = pos[k3 + 2] - sz / fn
            let d = (dx * dx + dy * dy + dz * dz).squareRoot()
            if d > kink {
                hits += 1
                let s = min(0.7, (d - ktarget) / d)
                fix[k3] = -dx * s; fix[k3 + 1] = -dy * s; fix[k3 + 2] = -dz * s
            }
        }
        kinkN = hits
        guard hits > 0 else { return }
        for i in 0..<(3 * count) where fix[i] != 0 {
            pos[i] += fix[i]
            prev[i] += fix[i]
        }
    }

    private func computeNormals() {
        normal.update(repeating: 0, count: count * 3)
        indices.withUnsafeBufferPointer { ib in
            var t = 0
            while t < ib.count {
                let ia = 3 * Int(ib[t]), ibx = 3 * Int(ib[t + 1]), ic = 3 * Int(ib[t + 2])
                let pa = SIMD3<Float>(pos[ia], pos[ia + 1], pos[ia + 2])
                let pb = SIMD3<Float>(pos[ibx], pos[ibx + 1], pos[ibx + 2])
                let pc = SIMD3<Float>(pos[ic], pos[ic + 1], pos[ic + 2])
                let f = cross(pc - pb, pa - pb)
                normal[ia] += f.x; normal[ia + 1] += f.y; normal[ia + 2] += f.z
                normal[ibx] += f.x; normal[ibx + 1] += f.y; normal[ibx + 2] += f.z
                normal[ic] += f.x; normal[ic + 1] += f.y; normal[ic + 2] += f.z
                t += 3
            }
        }
        for k in 0..<count {
            let k3 = 3 * k
            let v = SIMD3<Float>(normal[k3], normal[k3 + 1], normal[k3 + 2])
            let len = simd_length(v)
            if len > 1e-9 {
                normal[k3] = v.x / len; normal[k3 + 1] = v.y / len; normal[k3 + 2] = v.z / len
            } else {
                normal[k3] = 0; normal[k3 + 1] = 0; normal[k3 + 2] = 1
            }
        }
    }

    func beginGrab(atLocal g: SIMD3<Float>, liftDirection: SIMD3<Float>) {
        grabN = 0
        let r2 = grabRadius * grabRadius
        for k in 0..<count {
            let k3 = 3 * k
            let dx = pos[k3] - g.x, dy = pos[k3 + 1] - g.y, dz = pos[k3 + 2] - g.z
            let d2 = dx * dx + dy * dy + dz * dz
            if d2 < r2 {
                let t = 1 - d2.squareRoot() / grabRadius
                grabIdx[grabN] = Int32(k3)
                grabW[grabN] = t * t * (3 - 2 * t)
                grabOff[3 * grabN] = dx; grabOff[3 * grabN + 1] = dy; grabOff[3 * grabN + 2] = dz
                grabN += 1
            }
        }
        grabLiftVec = simd_normalize(liftDirection) * grabLift
        grabTarget = g
    }

    func moveGrab(toLocal t: SIMD3<Float>) { grabTarget = t }

    func endGrab() { grabN = 0 }

    func nearestVertex(toNDC p: SIMD2<Float>, project: (SIMD3<Float>) -> SIMD2<Float>) -> SIMD3<Float> {
        var best = SIMD3<Float>(pos[0], pos[1], pos[2])
        var bd = Float.greatestFiniteMagnitude
        for k in 0..<count {
            let k3 = 3 * k
            let v = SIMD3<Float>(pos[k3], pos[k3 + 1], pos[k3 + 2])
            let s = project(v) - p
            let d = simd_length_squared(s)
            if d < bd { bd = d; best = v }
        }
        return best
    }

    func raycastLocal(origin o: SIMD3<Float>, direction d: SIMD3<Float>) -> SIMD3<Float>? {
        var bestT = Float.greatestFiniteMagnitude
        var hit: SIMD3<Float>?
        indices.withUnsafeBufferPointer { ib in
            var t = 0
            while t < ib.count {
                let ia = 3 * Int(ib[t]), ibx = 3 * Int(ib[t + 1]), ic = 3 * Int(ib[t + 2])
                let v0 = SIMD3<Float>(pos[ia], pos[ia + 1], pos[ia + 2])
                let v1 = SIMD3<Float>(pos[ibx], pos[ibx + 1], pos[ibx + 2])
                let v2 = SIMD3<Float>(pos[ic], pos[ic + 1], pos[ic + 2])
                let e1 = v1 - v0, e2 = v2 - v0
                let p = cross(d, e2)
                let det = simd_dot(e1, p)
                if abs(det) < 1e-9 { t += 3; continue }
                let inv = 1 / det
                let tv = o - v0
                let u = simd_dot(tv, p) * inv
                if u < 0 || u > 1 { t += 3; continue }
                let q = cross(tv, e1)
                let vv = simd_dot(d, q) * inv
                if vv < 0 || u + vv > 1 { t += 3; continue }
                let dist = simd_dot(e2, q) * inv
                if dist > 1e-5 && dist < bestT { bestT = dist; hit = o + d * dist }
                t += 3
            }
        }
        return hit
    }
}
