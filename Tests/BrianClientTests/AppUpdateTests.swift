@testable import BrianClient
import Foundation
import XCTest

final class AppUpdateTests: XCTestCase {
    func testLaunchCheckSelectsTheNewestInstallableRelease() throws {
        let feed = """
        {
          "items": [
            {
              "version": "0.2.0",
              "build": "2",
              "minimumSystemVersion": "14.0",
              "downloadURL": "https://github.com/embeputer/brian-desktop/releases/download/v0.2.0/Brian.dmg",
              "releaseNotes": "Fixes the composer.",
              "length": 1200
            },
            {
              "version": "0.3.0",
              "build": 3,
              "minimumSystemVersion": "15.0",
              "downloadURL": "https://github.com/embeputer/brian-desktop/releases/download/v0.3.0/Brian.dmg",
              "releaseNotes": "Needs a newer macOS."
            },
            {
              "version": "0.1.0",
              "build": "1",
              "downloadURL": "https://example.com/old.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let decision = try ReleaseFeed.decide(
            data: feed,
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.6.1"
        )
        guard case .available(let item) = decision else {
            return XCTFail("expected an installable update, got \(decision)")
        }
        XCTAssertEqual(item.version, "0.2.0")
        XCTAssertEqual(item.build, "2")
        XCTAssertEqual(item.minimumSystemVersion, "14.0")
        XCTAssertEqual(item.releaseNotes, "Fixes the composer.")
        XCTAssertEqual(item.length, 1200)
        XCTAssertEqual(
            item.downloadURL.absoluteString,
            "https://github.com/embeputer/brian-desktop/releases/download/v0.2.0/Brian.dmg"
        )
    }

    func testSameVersionIsUpToDateAndAHigherBuildIsNot() throws {
        let same = try ReleaseFeed.decide(
            data: itemJSON(version: "0.1.0", build: "1"),
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.0"
        )
        XCTAssertEqual(same, .upToDate)

        let newerBuild = try ReleaseFeed.decide(
            data: itemJSON(version: "0.1.0", build: "2"),
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.0"
        )
        guard case .available(let item) = newerBuild else {
            return XCTFail("expected build 2")
        }
        XCTAssertEqual(item.build, "2")

        let older = try ReleaseFeed.decide(
            data: itemJSON(version: "0.0.9", build: "99"),
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.0"
        )
        XCTAssertEqual(older, .upToDate)
    }

    func testVersionsCompareNumerically() throws {
        let decision = try ReleaseFeed.decide(
            data: itemJSON(version: "0.10.0", build: "10"),
            currentVersion: "0.9.0",
            currentBuild: "9",
            systemVersion: "14.0"
        )
        guard case .available(let item) = decision else {
            return XCTFail("0.10.0 is newer than 0.9.0")
        }
        XCTAssertEqual(item.version, "0.10.0")
    }

    func testNewerReleaseThatNeedsANewerSystemIsReported() throws {
        let decision = try ReleaseFeed.decide(
            data: itemJSON(version: "0.3.0", build: "3", minimumSystemVersion: "15.0"),
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.6"
        )
        XCTAssertEqual(decision, .requiresNewerSystem(version: "0.3.0", minimumSystemVersion: "15.0"))
    }

    func testFeedSkipsUnsafeDownloadsAndUnreadableJSONThrows() throws {
        let skipped = try ReleaseFeed.decide(
            data: """
            {"items":[
              {"version":"9.0.0","build":"9","downloadURL":"http://example.com/Brian.dmg"},
              {"version":"9.0.0","build":"9","downloadURL":"https://example.com/Brian.txt"},
              {"version":"9.0.0","build":"9","downloadURL":"https://user:pass@example.com/Brian.dmg"},
              {"version":"9.0.0","build":"9","downloadURL":"https://example.com/Brian.dmg","length":250000001}
            ]}
            """.data(using: .utf8)!,
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.0"
        )
        XCTAssertEqual(skipped, .upToDate)

        XCTAssertThrowsError(try ReleaseFeed.decide(
            data: Data("not json".utf8),
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.0"
        )) { error in
            XCTAssertEqual(error as? BrianClientError, BrianClientError(message: "The release feed could not be read."))
        }
    }

    func testSingleItemAndZipAreAccepted() throws {
        let decision = try ReleaseFeed.decide(
            data: """
            {"version":"0.2.0","build":"2","downloadURL":"https://example.com/Brian.ZIP","releaseNotes":"Zip build."}
            """.data(using: .utf8)!,
            currentVersion: "0.1.0",
            currentBuild: "1",
            systemVersion: "14.0"
        )
        guard case .available(let item) = decision else {
            return XCTFail("expected the zip item")
        }
        XCTAssertEqual(item.downloadURL.pathExtension.lowercased(), "zip")
        XCTAssertEqual(item.releaseNotes, "Zip build.")
    }

    func testFeedURLPrefersTheEnvironmentThenTheBundleThenTheDefault() {
        XCTAssertEqual(
            ReleaseFeed.resolvedURL(infoFeed: nil, environment: [:]),
            ReleaseFeed.defaultURL
        )
        XCTAssertEqual(
            ReleaseFeed.defaultURL.absoluteString,
            "https://github.com/embeputer/brian-desktop/releases/latest/download/appcast.json"
        )
        let plist = "https://updates.example/brian/appcast.json"
        XCTAssertEqual(
            ReleaseFeed.resolvedURL(infoFeed: plist, environment: [:]).absoluteString,
            plist
        )
        XCTAssertEqual(
            ReleaseFeed.resolvedURL(
                infoFeed: plist,
                environment: ["BRIAN_UPDATE_FEED": "https://staging.example/appcast.json"]
            ).absoluteString,
            "https://staging.example/appcast.json"
        )
        XCTAssertEqual(
            ReleaseFeed.resolvedURL(
                infoFeed: "http://insecure.example/appcast.json",
                environment: ["BRIAN_UPDATE_FEED": "not a url"]
            ),
            ReleaseFeed.defaultURL
        )
    }

    func testPromptCopyForAnAvailableUpdate() {
        XCTAssertEqual(UpdatePromptCopy.availableTitle, "A new version of Brian is available")
        XCTAssertEqual(
            UpdatePromptCopy.availableMessage(offeredVersion: "0.2.0", currentVersion: "0.1.0"),
            "Brian 0.2.0 is now available — you have 0.1.0. Would you like to download it now?"
        )
        XCTAssertEqual(UpdatePromptCopy.installButton, "Install Update")
        XCTAssertEqual(UpdatePromptCopy.laterButton, "Later")
        XCTAssertEqual(UpdatePromptCopy.releaseNotesHeading, "Release notes")
        XCTAssertEqual(UpdatePromptCopy.downloadingTitle(version: "0.2.0"), "Downloading Brian 0.2.0")
        XCTAssertEqual(UpdatePromptCopy.readyTitle(version: "0.2.0"), "Brian 0.2.0 is ready to install")
        XCTAssertEqual(UpdatePromptCopy.readyMessage, "Brian will quit, replace this copy, and reopen.")
        XCTAssertEqual(UpdatePromptCopy.relaunchButton, "Install and Relaunch")
        XCTAssertEqual(UpdatePromptCopy.upToDateTitle, "Brian is up to date")
        XCTAssertEqual(UpdatePromptCopy.upToDateMessage(version: "0.1.0"), "You're running Brian 0.1.0.")
        XCTAssertEqual(UpdatePromptCopy.checkForUpdatesMenu, "Check for Updates…")
        XCTAssertEqual(
            UpdatePromptCopy.requiresNewerSystem(version: "0.3.0", minimum: "15.0"),
            "Brian 0.3.0 requires macOS 15.0 or later."
        )
    }

    func testPackagedVersionMatchesTheAppPlistAndFeed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = root.appendingPathComponent("Scripts/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, AppVersion.packaged.version)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, AppVersion.packaged.build)
        XCTAssertEqual(plist["SUFeedURL"] as? String, ReleaseFeed.defaultURL.absoluteString)
        XCTAssertEqual(AppVersion.current(info: nil), AppVersion.packaged)
        XCTAssertEqual(
            AppVersion.current(info: ["CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "14"]),
            AppVersion(version: "1.4.0", build: "14")
        )
    }

    func testDownloadFractionClampsToTheFileSize() {
        XCTAssertEqual(UpdateDownload.fraction(received: 0, expected: nil), 0)
        XCTAssertEqual(UpdateDownload.fraction(received: 50, expected: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(UpdateDownload.fraction(received: 150, expected: 100), 1, accuracy: 0.0001)
        XCTAssertEqual(UpdateDownload.maximumBytes, 250_000_000)
    }

    func testInstallReplacesTheRunningAppOrFallsBackToApplications() {
        var links: Set<String> = []
        var writable: Set<String> = ["/Applications", "/tmp/Brian.app".parentPath]
        let running = URL(fileURLWithPath: "/tmp/Brian.app")
        XCTAssertEqual(
            AppUpdateInstaller.destination(
                runningBundle: running,
                applicationsDirectory: URL(fileURLWithPath: "/Applications"),
                userApplicationsDirectory: URL(fileURLWithPath: "/Users/me/Applications"),
                isWritableDirectory: { writable.contains($0.path) },
                isSymbolicLink: { links.contains($0.path) }
            ).path,
            "/tmp/Brian.app"
        )

        links.insert("/tmp/Brian.app")
        XCTAssertEqual(
            AppUpdateInstaller.destination(
                runningBundle: running,
                applicationsDirectory: URL(fileURLWithPath: "/Applications"),
                userApplicationsDirectory: URL(fileURLWithPath: "/Users/me/Applications"),
                isWritableDirectory: { writable.contains($0.path) },
                isSymbolicLink: { links.contains($0.path) }
            ).path,
            "/Applications/Brian.app"
        )

        writable.remove("/Applications")
        XCTAssertEqual(
            AppUpdateInstaller.destination(
                runningBundle: URL(fileURLWithPath: "/repo/.build/debug/BrianDesktop"),
                applicationsDirectory: URL(fileURLWithPath: "/Applications"),
                userApplicationsDirectory: URL(fileURLWithPath: "/Users/me/Applications"),
                isWritableDirectory: { writable.contains($0.path) },
                isSymbolicLink: { _ in false }
            ).path,
            "/Users/me/Applications/Brian.app"
        )
    }

    func testStageCopiesAValidatedAppAndRejectsTheWrongBundle() throws {
        let fixture = try UpdateFixture()
        let item = feedItem(version: "0.2.0", build: "2")
        let root = fixture.directory.appendingPathComponent("mounted")
        let source = try writeApp(at: root, version: "0.2.0", build: "2")
        let staging = fixture.directory.appendingPathComponent("staging")
        let prepared = try AppUpdateInstaller.stage(
            contentsRoot: root,
            item: item,
            runningBundle: URL(fileURLWithPath: "/Applications/Brian.app"),
            applicationsDirectory: URL(fileURLWithPath: "/Applications"),
            userApplicationsDirectory: fixture.directory.appendingPathComponent("Applications"),
            stagingDirectory: staging,
            fileManager: .default,
            isWritableDirectory: { $0.path == "/Applications" },
            isSymbolicLink: { _ in false }
        )
        XCTAssertEqual(prepared.destination.path, "/Applications/Brian.app")
        XCTAssertEqual(prepared.version, "0.2.0")
        XCTAssertEqual(prepared.build, "2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.stagedApp.appendingPathComponent("Contents/MacOS/BrianDesktop").path))
        XCTAssertEqual(prepared.stagedApp.deletingLastPathComponent().standardizedFileURL.path, staging.standardizedFileURL.path)
        XCTAssertNotEqual(prepared.stagedApp.standardizedFileURL.path, source.standardizedFileURL.path)

        let wrong = fixture.directory.appendingPathComponent("wrong")
        _ = try writeApp(at: wrong, version: "0.2.0", build: "2", bundleID: "com.example.other")
        XCTAssertThrowsError(try AppUpdateInstaller.stage(
            contentsRoot: wrong,
            item: item,
            runningBundle: nil,
            applicationsDirectory: URL(fileURLWithPath: "/Applications"),
            userApplicationsDirectory: fixture.directory.appendingPathComponent("Applications"),
            stagingDirectory: fixture.directory.appendingPathComponent("staging-wrong"),
            fileManager: .default,
            isWritableDirectory: { _ in true },
            isSymbolicLink: { _ in false }
        )) { error in
            XCTAssertEqual(error as? BrianClientError, BrianClientError(message: "The downloaded app is not Brian."))
        }
    }

    func testStageRejectsAVersionMismatchAMissingAppAndASymlinkEscape() throws {
        let fixture = try UpdateFixture()
        let item = feedItem(version: "0.2.0", build: "2")
        let mismatch = fixture.directory.appendingPathComponent("mismatch")
        _ = try writeApp(at: mismatch, version: "0.9.0", build: "9")
        XCTAssertThrowsError(try stage(contents: mismatch, item: item, fixture: fixture, name: "stage-mismatch")) { error in
            XCTAssertEqual(
                error as? BrianClientError,
                BrianClientError(message: "The downloaded app is a different version than the feed announced.")
            )
        }

        let empty = fixture.directory.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try stage(contents: empty, item: item, fixture: fixture, name: "stage-empty")) { error in
            XCTAssertEqual(error as? BrianClientError, BrianClientError(message: "The update does not contain Brian.app."))
        }

        let outside = fixture.directory.appendingPathComponent("outside")
        _ = try writeApp(at: outside, version: "0.2.0", build: "2")
        let linked = fixture.directory.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("Brian.app"),
            withDestinationURL: outside.appendingPathComponent("Brian.app")
        )
        XCTAssertThrowsError(try stage(contents: linked, item: item, fixture: fixture, name: "stage-link")) { error in
            XCTAssertEqual(
                error as? BrianClientError,
                BrianClientError(message: "The downloaded app is not inside the update.")
            )
        }
    }

    func testDiskImageMountPointAndExtractor() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>system-entities</key><array>
          <dict><key>dev-entry</key><string>/dev/disk4</string></dict>
          <dict>
            <key>dev-entry</key><string>/dev/disk4s1</string>
            <key>mount-point</key><string>/Volumes/Install Brian</string>
          </dict>
        </array></dict></plist>
        """.data(using: .utf8)!
        XCTAssertEqual(try UpdateArchive.mountPoint(fromHdiutilPlist: plist).path, "/Volumes/Install Brian")

        let fixture = try UpdateFixture()
        let archive = fixture.directory.appendingPathComponent("Brian.dmg")
        try Data("dmg".utf8).write(to: archive)
        let mount = fixture.directory.appendingPathComponent("mount")
        let runner = ScriptedUpdateRunner { executable, arguments in
            XCTAssertEqual(executable.path, "/usr/bin/hdiutil")
            XCTAssertEqual(arguments, ["attach", "-nobrowse", "-readonly", "-plist", archive.path])
            let body = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>system-entities</key><array><dict>
              <key>mount-point</key><string>\(mount.path)</string>
            </dict></array></dict></plist>
            """
            return CommandOutput(status: 0, stdout: body, stderr: "")
        }
        let extracted = try UpdateArchive.extract(
            archive: archive,
            workDirectory: fixture.directory.appendingPathComponent("work"),
            runner: runner,
            fileManager: .default
        )
        XCTAssertEqual(extracted.contentsRoot.path, mount.path)
        XCTAssertEqual(extracted.mountPoint?.path, mount.path)
        XCTAssertEqual(UpdateArchive.detachArguments(mountPoint: mount), ["detach", mount.path])
    }

    func testZipExtractorAsksDittoToExpandIntoTheWorkDirectory() throws {
        let fixture = try UpdateFixture()
        let archive = fixture.directory.appendingPathComponent("Brian.zip")
        try Data("zip".utf8).write(to: archive)
        let work = fixture.directory.appendingPathComponent("work")
        let runner = ScriptedUpdateRunner { executable, arguments in
            XCTAssertEqual(executable.path, "/usr/bin/ditto")
            let destination = work.appendingPathComponent("unzipped")
            XCTAssertEqual(arguments, ["-xk", archive.path, destination.path])
            _ = try self.writeApp(at: destination, version: "0.2.0", build: "2")
            return CommandOutput(status: 0, stdout: "", stderr: "")
        }
        let extracted = try UpdateArchive.extract(archive: archive, workDirectory: work, runner: runner, fileManager: .default)
        XCTAssertNil(extracted.mountPoint)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.contentsRoot.appendingPathComponent("Brian.app/Contents/Info.plist").path))
    }

    func testRelaunchCommandWaitsForThisProcessThenReplacesTheApp() {
        XCTAssertTrue(UpdateRelaunch.script.contains("kill -0"))
        XCTAssertTrue(UpdateRelaunch.script.contains("ditto"))
        XCTAssertTrue(UpdateRelaunch.script.contains("open"))
        XCTAssertTrue(UpdateRelaunch.script.contains("com.apple.quarantine"))
        XCTAssertFalse(UpdateRelaunch.script.contains("/Applications"))

        let command = UpdateRelaunch.command(
            scriptURL: URL(fileURLWithPath: "/tmp/brian-update/install.sh"),
            pid: 4321,
            stagedApp: URL(fileURLWithPath: "/tmp/brian-update/Brian.app"),
            destination: URL(fileURLWithPath: "/Applications/Brian.app"),
            cleanup: URL(fileURLWithPath: "/tmp/brian-update")
        )
        XCTAssertEqual(command.executable.path, "/usr/bin/nohup")
        XCTAssertEqual(command.arguments, [
            "/tmp/brian-update/install.sh",
            "4321",
            "/tmp/brian-update/Brian.app",
            "/Applications/Brian.app",
            "/tmp/brian-update",
        ])
    }

    func testHTTPResponseMustStayOnHTTPS() throws {
        try ReleaseFeed.validateHTTP(statusCode: 200, finalURL: URL(string: "https://example.com/appcast.json"))
        XCTAssertThrowsError(try ReleaseFeed.validateHTTP(statusCode: 404, finalURL: URL(string: "https://example.com/missing")))
        XCTAssertThrowsError(try ReleaseFeed.validateHTTP(statusCode: 200, finalURL: URL(string: "http://example.com/appcast.json")))
    }

    private func itemJSON(version: String, build: String, minimumSystemVersion: String? = nil) -> Data {
        var item = """
        {"version":"\(version)","build":"\(build)","downloadURL":"https://example.com/Brian.dmg"
        """
        if let minimumSystemVersion {
            item += ",\"minimumSystemVersion\":\"\(minimumSystemVersion)\""
        }
        item += "}"
        return Data(item.utf8)
    }

    private func feedItem(version: String, build: String) -> ReleaseFeedItem {
        ReleaseFeedItem(
            version: version,
            build: build,
            minimumSystemVersion: "14.0",
            downloadURL: URL(string: "https://example.com/Brian.dmg")!,
            releaseNotes: "",
            length: nil
        )
    }

    private func stage(contents: URL, item: ReleaseFeedItem, fixture: UpdateFixture, name: String) throws -> PreparedUpdate {
        try AppUpdateInstaller.stage(
            contentsRoot: contents,
            item: item,
            runningBundle: nil,
            applicationsDirectory: URL(fileURLWithPath: "/Applications"),
            userApplicationsDirectory: fixture.directory.appendingPathComponent("Applications"),
            stagingDirectory: fixture.directory.appendingPathComponent(name),
            fileManager: .default,
            isWritableDirectory: { _ in true },
            isSymbolicLink: { _ in false }
        )
    }

    private func writeApp(at root: URL, version: String, build: String, bundleID: String = "dev.brian.desktop") throws -> URL {
        let app = root.appendingPathComponent("Brian.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
          <key>CFBundleVersion</key><string>\(build)</string>
          <key>CFBundleExecutable</key><string>BrianDesktop</string>
        </dict></plist>
        """
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try Data("#!/bin/sh\n".utf8).write(to: macos.appendingPathComponent("BrianDesktop"))
        return app
    }
}

private final class UpdateFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("brian-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private extension String {
    var parentPath: String {
        URL(fileURLWithPath: self).deletingLastPathComponent().path
    }
}

private final class ScriptedUpdateRunner: CommandRunning {
    let handler: (URL, [String]) throws -> CommandOutput

    init(handler: @escaping (URL, [String]) throws -> CommandOutput) {
        self.handler = handler
    }

    func run(executable: URL, arguments: [String], environment: [String: String]) throws -> CommandOutput {
        try handler(executable, arguments)
    }
}
