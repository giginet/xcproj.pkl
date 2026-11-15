import Foundation
import Testing

@testable import XcprojPkl

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to validate the runnable examples"))
struct ExampleTests {
    @Test func iOSMainInheritsSwift6AndEmbedsFrameworksAndNotificationService() throws {
        let fixture = try Fixture()
        let plan = try GenerationPlan.compile(
            source: repository.appendingPathComponent("Examples/iOS/Main.pkl"),
            outputDirectory: fixture.root.appendingPathComponent("Generated"))
        #expect(plan.targetCount == 6)
        let json = try #require(
            JSONSerialization.jsonObject(with: plan.projects[0].data) as? [String: Any])
        let targets = try #require(json["targets"] as? [[String: Any]])
        func target(_ name: String) throws -> [String: Any] {
            try #require(targets.first { $0["name"] as? String == name })
        }
        func settings(_ name: String) throws -> [String: Any] {
            try #require(target(name)["build-settings"] as? [String: Any])
        }
        for item in targets {
            let settings = try #require(item["build-settings"] as? [String: Any])
            #expect(settings["SWIFT_VERSION"] as? String == "6.0")
            #expect(settings["OTHER_SWIFT_FLAGS"] as? [String] == ["$(inherited)", "-DTEAM"])
        }
        for name in ["DemoCore", "DemoNetworking", "DemoNotifications"] {
            #expect(try target(name)["product-type"] as? String == "framework")
        }
        #expect(
            try settings("DemoNotifications")["APPLICATION_EXTENSION_API_ONLY"] as? String == "YES")
        let service = try target("DemoNotificationService")
        #expect(service["product-type"] as? String == "app-extension")
        let serviceSettings = try settings("DemoNotificationService")
        #expect(serviceSettings["APPLICATION_EXTENSION_API_ONLY"] as? String == "YES")
        #expect(serviceSettings["GENERATE_INFOPLIST_FILE"] as? String == "NO")
        let appID = try #require(settings("DemoApp")["PRODUCT_BUNDLE_IDENTIFIER"] as? String)
        let serviceID = try #require(serviceSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String)
        #expect(serviceID.hasPrefix(appID + "."))
        let plist = try #require(serviceSettings["INFOPLIST_FILE"] as? String)
        let resolved = URL(
            fileURLWithPath: plist, relativeTo: plan.destination.deletingLastPathComponent())
        #expect(
            canonicalFileURL(resolved)
                == canonicalFileURL(
                    repository.appendingPathComponent(
                        "Examples/iOS/Config/NotificationService-Info.plist")))
        let phases = try #require(target("DemoApp")["build-phases"] as? [Any])
            .compactMap { $0 as? [String: Any] }
        #expect(
            phases.contains {
                $0["name"] as? String == "Embed Frameworks"
                    && $0["bundle-base-path"] as? String == "frameworks-directory"
            })
        #expect(
            phases.contains {
                $0["name"] as? String == "Embed App Extensions"
                    && $0["bundle-base-path"] as? String == "plugins-directory"
            })
        let references = try #require(json["files"] as? [[String: Any]])
        let products = try #require(
            references.first { $0["name"] as? String == "Products" }?["children"]
                as? [[String: Any]])
        let appex = try #require(
            products.first { $0["type"] as? String == "wrapper.app-extension" })
        #expect(appex["path"] as? String == "<PRODUCTS>/DemoNotificationService.appex")
        let memberships = try #require(appex["target-membership"] as? [[String: Any]])
        #expect(
            memberships.contains {
                $0["build-phase"] as? String == "DemoApp/copy/Embed App Extensions"
            })
        try plan.write()
        #expect(try Data(contentsOf: plan.projects[0].destination) == plan.projects[0].data)
    }

    @Test(arguments: ["link", "embed", "missing-plist"])
    func invalidAppExtensionDependenciesAndPlistAreRejected(_ kind: String) throws {
        let fixture = try Fixture()
        let body: String
        let message: String
        switch kind {
        case "link":
            body = #"""
                targets {
                    ["app"] { name = "App"; type = "application"; platform = "iOS"; dependencies { new { target = "service" } } }
                    ["service"] { name = "Service"; type = "app-extension"; platform = "iOS" }
                }
                """#
            message = "only frameworks can be linked"
        case "embed":
            body = #"""
                targets {
                    ["framework"] { name = "Framework"; type = "framework"; platform = "iOS"; dependencies { new { target = "service"; link = false; embed = true } } }
                    ["service"] { name = "Service"; type = "app-extension"; platform = "iOS" }
                }
                """#
            message = "embedding"
        default:
            body =
                #"targets { ["service"] { name = "Service"; type = "app-extension"; platform = "iOS"; infoPlist = "Missing.plist" } }"#
            message = "infoPlist: file does not exist"
        }
        expectFailure(containing: message) { _ = try fixture.compile(body) }
    }
}
