// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import SwiftUI

enum BrandColors {
    static let canvasTop = Color(red: 0.02, green: 0.10, blue: 0.13)
    static let canvasBottom = Color(red: 0.05, green: 0.22, blue: 0.26)
    static let frameStart = Color(red: 0.40, green: 0.96, blue: 0.90)
    static let frameEnd = Color(red: 0.11, green: 0.79, blue: 0.83)
    static let tunnelOuter = Color(red: 0.09, green: 0.26, blue: 0.30)
    static let tunnelInner = Color(red: 0.05, green: 0.16, blue: 0.19)
    static let beamCore = Color(red: 0.90, green: 1.00, blue: 0.97)
    static let beamEdge = Color(red: 0.41, green: 0.94, blue: 0.90)
}

struct PortalHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.08
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let hw = bounds.width / 2
        let hh = bounds.height / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        return Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y - hh))
            path.addLine(to: CGPoint(x: center.x + hw, y: center.y - hh * 0.42))
            path.addLine(to: CGPoint(x: center.x + hw, y: center.y + hh * 0.42))
            path.addLine(to: CGPoint(x: center.x, y: center.y + hh))
            path.addLine(to: CGPoint(x: center.x - hw, y: center.y + hh * 0.42))
            path.addLine(to: CGPoint(x: center.x - hw, y: center.y - hh * 0.42))
            path.closeSubpath()
        }
    }
}

struct BrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let stroke = size * 0.11
            let beamWidth = size * 0.19
            let beamHeight = size * 0.56
            let coreWidth = beamWidth * 0.38
            let dot = size * 0.16

            ZStack {
                PortalHexagon()
                    .fill(BrandColors.tunnelOuter.opacity(0.45))

                PortalHexagon()
                    .stroke(
                        LinearGradient(
                            colors: [BrandColors.frameStart, BrandColors.frameEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: stroke, lineJoin: .round)
                    )
                    .shadow(color: BrandColors.frameStart.opacity(0.34), radius: size * 0.06)

                PortalHexagon()
                    .fill(BrandColors.tunnelOuter.opacity(0.85))
                    .scaleEffect(0.78)

                PortalHexagon()
                    .fill(BrandColors.tunnelInner)
                    .scaleEffect(0.58)

                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.beamCore, BrandColors.beamEdge],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: beamWidth, height: beamHeight)

                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: coreWidth, height: beamHeight * 0.98)
                }
                .rotationEffect(.degrees(-45))
                .offset(x: size * 0.06, y: size * 0.06)
                .clipShape(ScaledShape(shape: PortalHexagon(), scale: CGSize(width: 0.58, height: 0.58)))
                .shadow(color: BrandColors.frameStart.opacity(0.25), radius: size * 0.05)

                Circle()
                    .fill(BrandColors.beamCore)
                    .overlay {
                        Circle()
                            .fill(BrandColors.frameEnd)
                            .padding(dot * 0.24)
                    }
                    .frame(width: dot, height: dot)
                    .offset(x: size * 0.25, y: -size * 0.08)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct BrandBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandColors.canvasTop, BrandColors.canvasBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(BrandColors.frameStart.opacity(0.16))
                .blur(radius: size * 0.08)
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(x: size * 0.16, y: -size * 0.14)

            BrandMark()
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .shadow(color: BrandColors.canvasTop.opacity(0.18), radius: size * 0.08, y: size * 0.03)
    }
}

struct BrandHeader: View {
    let profileCount: Int

    var body: some View {
        HStack(spacing: 16) {
            BrandBadge(size: 74)

            VStack(alignment: .leading, spacing: 4) {
                Text("dsvpn")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Private tunnel client")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.3)
            }

            Spacer(minLength: 12)

            if profileCount > 0 {
                Text("\(profileCount) profile\(profileCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("AccentColor"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color("AccentColor").opacity(0.12))
                    )
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color("Surface"), Color("SurfaceElevated")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color("AccentColor").opacity(0.14))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)
                        .offset(x: 26, y: -26)
                }
        }
    }
}
