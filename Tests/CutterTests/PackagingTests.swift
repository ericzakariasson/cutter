import Foundation
import Testing

/// Checks on the files that decide what a release is. The scripts themselves are checked
/// end to end by `scripts/test-dmg.sh`.
@Suite struct PackagingTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.repository.appendingPathComponent(path), encoding: .utf8)
    }

    private func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repository.appendingPathComponent("Support/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// The app and the DMG's name both take the version from here.
    @Test func theVersionIsThreeNumbers() throws {
        let version = try #require(try infoPlist()["CFBundleShortVersionString"] as? String)
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
    }

    /// macOS files the Accessibility grant under this identifier. Changing it would make
    /// everyone grant access again, and would orphan their settings.
    @Test func theBundleIdentifierStaysTheSame() throws {
        #expect(try infoPlist()["CFBundleIdentifier"] as? String == "com.ericzakariasson.Cutter")
    }

    @Test func theMinimumSystemIsTheOneThePackageBuildsFor() throws {
        #expect(try infoPlist()["LSMinimumSystemVersion"] as? String == "13.0")
        #expect(try text("Package.swift").contains("platforms: [.macOS(.v13)]"))
    }

    @Test func theReleaseCertificateOnRecordIsAtMostOneFingerprint() throws {
        let lines = try text("Support/release-certificate.txt")
            .split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.allSatisfy(\.isWhitespace) }
        #expect(lines.count <= 1)
        for line in lines {
            #expect(line.count == 40)
            #expect(line.allSatisfy { "0123456789abcdef".contains($0) })
        }
    }

    /// Signing a DMG any way but with the release key must take a deliberate choice, and
    /// show in the file's name.
    @Test func packagingDefaultsToTheReleaseKey() throws {
        let script = try text("scripts/make-dmg.sh")
        #expect(script.contains(#"signing="${CUTTER_SIGNING:-release}""#))
        #expect(script.contains(#"dmg="$output/Cutter-$version-adhoc.dmg""#))
        #expect(script.contains(#"dmg="$output/Cutter-$version-local-key.dmg""#))
    }

    /// The release key must not share the build key's published password or folder.
    @Test func theReleaseKeyIsKeptApartFromTheBuildKey() throws {
        let setup = try text("scripts/setup-release-key.sh")
        #expect(!setup.contains("SIGNING_KEYCHAIN_PASSWORD"))
        #expect(!setup.contains("\"$SIGNING_KEYCHAIN\""))
        let settings = try text("scripts/signing.env")
        #expect(settings.contains("Cutter/release-signing"))
        #expect(settings.contains("Cutter/signing\""))
    }

    @Test func nothingBuiltOrPackagedIsCommitted() throws {
        let ignored = try text(".gitignore").split(separator: "\n").map(String.init)
        #expect(ignored.contains("dist/"))
        #expect(ignored.contains("build/"))
    }
}
