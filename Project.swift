import ProjectDescription

let project = Project(
    name: "dsvpn",
    organizationName: "pureftpd.org",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "888H8YF752",
        ]
    ),
    targets: [
        .target(
            name: "dsvpn",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "org.pureftpd.ios.dsvpn",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .file(path: "dsvpn/Info.plist"),
            sources: ["dsvpn/**"],
            resources: ["dsvpn/Assets.xcassets"],
            entitlements: .file(path: "dsvpn/dsvpn.entitlements"),
            dependencies: [
                .target(name: "dsvpnTunnel"),
            ]
        ),
        .target(
            name: "dsvpnTunnel",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "org.pureftpd.ios.dsvpn.tunnel",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .file(path: "dsvpnTunnel/Info.plist"),
            sources: ["dsvpnTunnel/**"],
            entitlements: .file(path: "dsvpnTunnel/dsvpnTunnel.entitlements"),
            settings: .settings(
                base: [
                    "SWIFT_OBJC_BRIDGING_HEADER": "dsvpnTunnel/dsvpnTunnel-Bridging-Header.h",
                ]
            )
        ),
    ],
    schemes: [
        .scheme(
            name: "dsvpn",
            buildAction: .buildAction(targets: ["dsvpn"]),
            runAction: .runAction(configuration: .release, executable: "dsvpn"),
            archiveAction: .archiveAction(configuration: .release),
            profileAction: .profileAction(configuration: .release, executable: "dsvpn")
        ),
    ]
)
