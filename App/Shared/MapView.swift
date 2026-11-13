import SwiftUI
import GezCore

/// Placeholder map: capitals drawn as colored dots on a simple
/// latitude/longitude projection of the game area. This gets replaced by the
/// Metal province-map renderer in the map milestone.
struct MapView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let _ = model.revision
        let world = model.world
        let selected = model.selectedProvince

        GeometryReader { geo in
            let projection = MapProjection(size: geo.size)
            Canvas { context, size in
                // Land backdrop for the game area.
                let backdrop = Path(roundedRect: projection.rect, cornerRadius: 8)
                context.fill(backdrop, with: .color(Palette.parchment.opacity(0.35)))

                // Grid lines every 10 degrees.
                var grid = Path()
                for lon in stride(from: MapProjection.minLon, through: MapProjection.maxLon, by: 10) {
                    grid.move(to: projection.point(GeoPoint(latitude: MapProjection.maxLat, longitude: lon)))
                    grid.addLine(to: projection.point(GeoPoint(latitude: MapProjection.minLat, longitude: lon)))
                }
                for lat in stride(from: MapProjection.minLat, through: MapProjection.maxLat, by: 10) {
                    grid.move(to: projection.point(GeoPoint(latitude: lat, longitude: MapProjection.minLon)))
                    grid.addLine(to: projection.point(GeoPoint(latitude: lat, longitude: MapProjection.maxLon)))
                }
                context.stroke(grid, with: .color(Palette.ink.opacity(0.08)), lineWidth: 0.5)

                let provinces = world.provinces
                let countries = world.countries
                for i in 0..<provinces.count {
                    let point = projection.point(provinces.location[i])
                    let isCapital = provinces.owner[i].map { countries.capital[$0.index] == ProvinceID(i) } ?? false
                    let radius: CGFloat = isCapital ? 7 : 5
                    let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    let color = provinces.owner[i].map { Palette.color(countries.color[$0.index]) } ?? .gray
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(selected == ProvinceID(i) ? .white : Palette.ink.opacity(0.7)),
                        lineWidth: selected == ProvinceID(i) ? 3 : 1
                    )
                    context.draw(
                        Text(provinces.name[i]).font(.system(size: 10, weight: .medium)).foregroundColor(Palette.ink),
                        at: CGPoint(x: point.x, y: point.y + radius + 7)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    model.selectedProvince = nearestProvince(to: value.location, projection: projection, world: world)
                }
            )
        }
    }

    private func nearestProvince(to location: CGPoint, projection: MapProjection, world: World) -> ProvinceID? {
        var best: (id: ProvinceID, distance: CGFloat)?
        for i in 0..<world.provinces.count {
            let p = projection.point(world.provinces.location[i])
            let d = hypot(p.x - location.x, p.y - location.y)
            if d < 24, d < (best?.distance ?? .infinity) {
                best = (ProvinceID(i), d)
            }
        }
        return best?.id
    }
}

/// Equirectangular projection of the game area, fitted into the view with
/// the correct aspect ratio and a small margin.
struct MapProjection {
    static let minLon = -20.0
    static let maxLon = 130.0
    static let minLat = 0.0
    static let maxLat = 70.0

    let rect: CGRect

    init(size: CGSize) {
        let margin: CGFloat = 16
        let available = CGSize(width: max(size.width - margin * 2, 1), height: max(size.height - margin * 2, 1))
        let aspect = (MapProjection.maxLon - MapProjection.minLon) / (MapProjection.maxLat - MapProjection.minLat)
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        rect = CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    func point(_ geo: GeoPoint) -> CGPoint {
        let x = (geo.longitude - MapProjection.minLon) / (MapProjection.maxLon - MapProjection.minLon)
        let y = (MapProjection.maxLat - geo.latitude) / (MapProjection.maxLat - MapProjection.minLat)
        return CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}
