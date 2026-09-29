import CoreGraphics

public struct ScrollSample: Equatable, Sendable {
    public var deltaX: CGFloat
    public var deltaY: CGFloat
    public var precise: Bool
    public var fingerDown: Bool
    public var inertial: Bool
    public init(deltaX: CGFloat, deltaY: CGFloat, precise: Bool, fingerDown: Bool, inertial: Bool) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.precise = precise
        self.fingerDown = fingerDown
        self.inertial = inertial
    }
}

public func specDeltas(scrollingDeltaX: CGFloat, scrollingDeltaY: CGFloat) -> (x: CGFloat, y: CGFloat) {
    (scrollingDeltaX, -scrollingDeltaY)
}

public struct ScrollAccumulator: Sendable {
    public var threshold: CGFloat
    private var accX: CGFloat
    private var accY: CGFloat

    public init(threshold: CGFloat = 80) {
        self.threshold = threshold
        accX = 0
        accY = 0
    }

    public mutating func consume(_ sample: ScrollSample) -> Int {
        if sample.inertial || (sample.precise && !sample.fingerDown) {
            accX = 0
            accY = 0
            return 0
        }
        if !sample.precise {
            accX = 0
            accY = 0
            if abs(sample.deltaX) >= abs(sample.deltaY) {
                if sample.deltaX == 0 { return 0 }
                return sample.deltaX > 0 ? 1 : -1
            }
            return sample.deltaY > 0 ? 1 : -1
        }
        accX += sample.deltaX
        accY += sample.deltaY
        let xHit = abs(accX) >= threshold
        let yHit = abs(accY) >= threshold
        guard xHit || yHit else { return 0 }
        let step: Int
        if xHit && (!yHit || abs(accX) > abs(accY)) {
            step = accX > 0 ? 1 : -1
        } else {
            step = accY > 0 ? 1 : -1
        }
        accX = 0
        accY = 0
        return step
    }
}
