//
//  Geohash.swift
//  Original by Maxim Veksler. Redistributed under MIT license.
//

enum Parity {
    case even, odd
}

prefix func ! (a: Parity) -> Parity {
    return a == .even ? .odd : .even
}

/// A geohash is a rectangular cell expressing a location using an ASCII string, the size of which is determined by how long the string is, the longer, the more precise.
public struct Geohash {
    // MARK: - Types
    enum CompassPoint {
        /// Top
        case north

        /// Bottom
        case south

        /// Right
        case east

        /// Left
        case west
    }

    public typealias Coordinates = (latitude: Double, longitude: Double)
    public typealias Hash = String

    // MARK: - Constants
    public static let defaultPrecision = 5
    private static let DecimalToBase32Map = Array("0123456789bcdefghjkmnpqrstuvwxyz") // decimal to 32base mapping (0 => "0", 31 => "z")
    private static let Base32BitflowInit: UInt8 = 0b10000

    // MARK: - Public properties
    public var coordinates: Coordinates {
        return (latitude, longitude)
    }

    /// The latitude value (measured in degrees) of the center of the cell.
    public var latitude: Double {
        return (self.north + self.south) / 2
    }

    /// The longitude value (measured in degrees) of the center of the cell.
    public var longitude: Double {
        return (self.east + self.west) / 2
    }

    /// The latitude/longitude delta (measured in degrees) of the cell, used for determining the dimensions of the cell.
    public var size: Coordinates {
        // * possible case examples:
        //
        // 1. bbox.north = 60, bbox.south = 40; point.latitude = 50, size.latitude = 20 ✅
        // 2. bbox.north = -40, bbox.south = -60; point.latitude = -50, size.latitude = 20 ✅
        // 3. bbox.north = 10, bbox.south = -10; point.latitude = 0, size.latitude = 20 ✅
        let latitude = north - south

        // * possible case examples:
        //
        // 1. bbox.east = 60, bbox.west = 40; point.longitude = 50, size.longitude = 20 ✅
        // 2. bbox.east = -40, bbox.west = -60; point.longitude = -50, size.longitude = 20 ✅
        // 3. bbox.east = 10, bbox.west = -10; point.longitude = 0, size.longitude = 20 ✅
        let longitude = east - west

        return (latitude: latitude, longitude: longitude)
    }

    public let geohash: Hash

    /// The number of characters in the hash.
    /// Refer to the table below for approximate cell size.
    /// ```
    /// Precision   Cell width      Cell height
    ///         1   ≤ 5,000km   x   5,000km
    ///         2   ≤ 1,250km   x   625km
    ///         3   ≤ 156km     x   156km
    ///         4   ≤ 39.1km    x   19.5km
    ///         5   ≤ 4.89km    x   4.89km
    ///         6   ≤ 1.22km    x   0.61km
    ///         7   ≤ 153m      x   153m
    ///         8   ≤ 38.2m     x   19.1m
    ///         9   ≤ 4.77m     x   4.77m
    ///        10   ≤ 1.19m     x   0.596m
    ///        11   ≤ 149mm     x   149mm
    ///        12   ≤ 37.2mm    x   18.6mm
    /// ```
    public var precision: Int {
        return geohash.count
    }

    // MARK: - Private properties
    let north: Double
    let west: Double
    let south: Double
    let east: Double

    // MARK: - Initializers

    /// Creates a geohash based on the provided coordinates and the requested precision.
    /// - parameter coordinates: The coordinates to use for generating the hash.
    /// - parameter precision: The number of characters to generate.
    ///     ```
    ///     Precision   Cell width      Cell height
    ///             1   ≤ 5,000km   x   5,000km
    ///             2   ≤ 1,250km   x   625km
    ///             3   ≤ 156km     x   156km
    ///             4   ≤ 39.1km    x   19.5km
    ///             5   ≤ 4.89km    x   4.89km
    ///             6   ≤ 1.22km    x   0.61km
    ///             7   ≤ 153m      x   153m
    ///             8   ≤ 38.2m     x   19.1m
    ///             9   ≤ 4.77m     x   4.77m
    ///            10   ≤ 1.19m     x   0.596m
    ///            11   ≤ 149mm     x   149mm
    ///            12   ≤ 37.2mm    x   18.6mm
    ///     ```
    /// - returns: If the specified coordinates are invalid, this returns nil.
    public init?(coordinates: Coordinates, precision: Int = Geohash.defaultPrecision) {
        var lat = (-90.0, 90.0)
        var lon = (-180.0, 180.0)

        // to be generated result.
        var generatedHash = Hash()

        // Loop helpers
        var parity_mode = Parity.even
        var base32char = 0
        var bit = Geohash.Base32BitflowInit

        repeat {
            switch parity_mode {
            case .even:
                let mid = (lon.0 + lon.1) / 2
                if coordinates.longitude >= mid {
                    base32char |= Int(bit)
                    lon.0 = mid
                } else {
                    lon.1 = mid
                }
            case .odd:
                let mid = (lat.0 + lat.1) / 2
                if coordinates.latitude >= mid {
                    base32char |= Int(bit)
                    lat.0 = mid
                } else {
                    lat.1 = mid
                }
            }

            // Flip between Even and Odd
            parity_mode = !parity_mode
            // And shift to next bit
            bit >>= 1

            if bit == 0b00000 {
                generatedHash += Hash(Geohash.DecimalToBase32Map[base32char])
                bit = Geohash.Base32BitflowInit // set next character round.
                base32char = 0
            }

        } while generatedHash.count < precision

        self.north = lat.1
        self.west = lon.0
        self.south = lat.0
        self.east = lon.1

        self.geohash = generatedHash
    }

    /// Try to create a geohash based on an existing hash. Useful for finding the center coordinate of the hash.
    /// - parameter hash: The existing hash to reverse hash.
    /// - returns: If the provided `hash` is invalid, this will return `nil`.
    public init?(geohash hash: Hash) {
        var parity_mode = Parity.even
        var lat = (-90.0, 90.0)
        var lon = (-180.0, 180.0)

        for c in hash {
            guard let bitmap = Geohash.DecimalToBase32Map.firstIndex(of: c) else {
                // Break on non geohash code char.
                return nil
            }

            var mask = Int(Geohash.Base32BitflowInit)
            while mask != 0 {

                switch parity_mode {
                case .even:
                    if bitmap & mask != 0 {
                        lon.0 = (lon.0 + lon.1) / 2
                    } else {
                        lon.1 = (lon.0 + lon.1) / 2
                    }
                case .odd:
                    if bitmap & mask != 0 {
                        lat.0 = (lat.0 + lat.1) / 2
                    } else {
                        lat.1 = (lat.0 + lat.1) / 2
                    }
                }

                parity_mode = !parity_mode
                mask >>= 1
            }
        }

        self.north = lat.1
        self.west = lon.0
        self.south = lat.0
        self.east = lon.1

        self.geohash = hash
    }

    // MARK: - Neighbors
    public struct Neighbors {
        public let origin: Geohash
        public let north: Geohash
        public let northeast: Geohash
        public let east: Geohash
        public let southeast: Geohash
        public let south: Geohash
        public let southwest: Geohash
        public let west: Geohash
        public let northwest: Geohash

        /// The neighboring geohashes sorted by compass direction in clockwise starting with `North`.
        public var all: [Geohash] {
            return [
                north,
                northeast,
                east,
                southeast,
                south,
                southwest,
                west,
                northwest
            ]
        }
    }

    /// - returns: The neighboring geohashes.
    public var neighbors: Neighbors? {
        guard
            let n = neighbor(direction: .north),    // N
            let s = neighbor(direction: .south),    // S
            let e = neighbor(direction: .east),     // E
            let w = neighbor(direction: .west),     // W
            let ne = n.neighbor(direction: .east),  // NE
            let nw = n.neighbor(direction: .west),  // NW
            let se = s.neighbor(direction: .east),  // SE
            let sw = s.neighbor(direction: .west)   // SW
        else { return nil }

        return Neighbors(origin: self, north: n, northeast: ne, east: e, southeast: se, south: s, southwest: sw, west: w, northwest: nw)
    }

    func neighbor(direction: CompassPoint) -> Geohash? {
        let latitude: Double
        let longitude: Double
        switch direction {
        case .north:
            latitude =  self.latitude + self.size.latitude // North is upper in the latitude scale
            longitude = self.longitude
        case .south:
            latitude =  self.latitude - self.size.latitude // South is lower in the latitude scale
            longitude = self.longitude
        case .east:
            latitude =  self.latitude
            longitude = self.longitude + self.size.longitude // East is bigger in the longitude scale
        case .west:
            latitude =  self.latitude
            longitude = self.longitude - self.size.longitude // West is lower in the longitude scale
        }

        return Geohash(coordinates: (latitude, longitude), precision: self.precision)
    }
}

extension Geohash: Hashable, Equatable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(geohash)
    }

    public static func == (lhs: Geohash, rhs: Geohash) -> Bool {
        return lhs.geohash == rhs.geohash
    }
}
