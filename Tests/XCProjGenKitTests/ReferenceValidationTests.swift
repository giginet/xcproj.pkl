import Foundation
import Testing

@testable import XCProjGenKit

private let referenceDocument = #"""
    {
      "configurations": ["Debug"], "default-configuration": "Debug",
      "products-group": null,
      "files": [
        {"path":"<PROJECT>/Remote.xcodeproj","id":"BBBBBBBBBBBBBBBBBBBBBBBB"},
        {"kind":"version-group","path":"<PROJECT>/Model.xcdatamodeld","current-version":"V2.xcdatamodel","children":[
          {"path":"V1.xcdatamodel","id":"EEEEEEEEEEEEEEEEEEEEEEEE"},
          {"path":"V2.xcdatamodel","id":"FFFFFFFFFFFFFFFFFFFFFFFF"}
        ]}
      ],
      "localizations": {"development":"en","supported":["Base"]},
      "imported-products":[{"name":"Remote.framework","project":"Remote.xcodeproj","target":"Remote","product-id":"DDDDDDDDDDDDDDDDDDDDDDDD","target-membership":["App/frameworks"]}],
      "targets": [{
        "name":"App","id":"AAAAAAAAAAAAAAAAAAAAAAAA","product-type":"tool",
        "build-phases":[{"kind":"frameworks","id":"CCCCCCCCCCCCCCCCCCCCCCCC"}],
        "build-rules":[{"processor":"com.apple.compilers.proxy.script","id":"111111111111111111111111"}],
        "dependencies":[{"kind":"remoteTarget","project":"Remote.xcodeproj","target":"Remote","target-id":"DDDDDDDDDDDDDDDDDDDDDDDD"}],
        "package-product-members":[{"package":"UnknownManifestName","product-name":"Library","build-phase":{"build-phase":"frameworks"}}]
      }, {
        "name":"Other","id":"333333333333333333333333","kind":"aggregate",
        "build-phases":[{"kind":"frameworks","id":"222222222222222222222222"}]
      }]
    }
    """#

struct ReferenceValidationTests {
    @Test(arguments: ["Products", "id:missing-products-group"])
    func missingProductsGroupIsRejected(_ reference: String) throws {
        let document = referenceDocument.replacingOccurrences(
            of: #""products-group": null"#,
            with: #""products-group": "# + quoted(reference))
        expectFailure(containing: "Products group") {
            _ = try ProjectValidator.validate(data: Data(document.utf8))
        }
    }

    @Test(arguments: [
        "V2.xcdatamodel", "./V2.xcdatamodel", "Model.xcdatamodeld/V2.xcdatamodel",
        "id:FFFFFFFFFFFFFFFFFFFFFFFF",
    ])
    func validLocalReferencesDoNotRequireExternalProjectsOrPackageManifests(_ version: String)
        throws
    {
        let document = referenceDocument.replacingOccurrences(
            of: #""current-version":"V2.xcdatamodel""#,
            with: #""current-version":""# + version + #"""#)
        #expect(try ProjectValidator.validate(data: Data(document.utf8)) == 2)
    }

    @Test(arguments: [
        "build-rule", "root-group", "project-config-list", "target-config-list",
        "package-build-file",
    ])
    func duplicateIDsInNewObjectTypesAreRejected(_ kind: String) throws {
        let document: String
        switch kind {
        case "build-rule":
            document = referenceDocument.replacingOccurrences(
                of: "111111111111111111111111", with: "AAAAAAAAAAAAAAAAAAAAAAAA")
        case "root-group":
            document = referenceDocument.replacingOccurrences(
                of: #""configurations": ["Debug"]"#,
                with:
                    #""root-group-debug-id":"AAAAAAAAAAAAAAAAAAAAAAAA", "configurations":["Debug"]"#
            )
        case "project-config-list":
            document = referenceDocument.replacingOccurrences(
                of: #""configurations": ["Debug"]"#,
                with:
                    #""configuration-list-debug-id":"AAAAAAAAAAAAAAAAAAAAAAAA", "configurations":["Debug"]"#
            )
        case "target-config-list":
            document = referenceDocument.replacingOccurrences(
                of: #""name":"App","id""#,
                with: #""name":"App","configuration-list-debug-id":"AAAAAAAAAAAAAAAAAAAAAAAA","id""#
            )
        default:
            document = referenceDocument.replacingOccurrences(
                of: #""build-phase":{"build-phase":"frameworks"}"#,
                with: #""build-phase":{"id":"AAAAAAAAAAAAAAAAAAAAAAAA","build-phase":"frameworks"}"#
            )
        }
        expectFailure(containing: "Duplicate object ID") {
            _ = try ProjectValidator.validate(data: Data(document.utf8))
        }
    }

    @Test(arguments: [
        "imported-product", "remote-target", "imported-membership", "package-phase",
        "package-other-target-phase", "version", "version-external-id",
    ])
    func danglingReferencesInNewObjectTypesAreRejected(_ kind: String) throws {
        let document: String
        let expected: String
        switch kind {
        case "imported-product":
            document = referenceDocument.replacingOccurrences(
                of: #""name":"Remote.framework","project":"Remote.xcodeproj""#,
                with: #""name":"Remote.framework","project":"Missing.xcodeproj""#)
            expected = "Imported product Remote.framework"
        case "remote-target":
            document = referenceDocument.replacingOccurrences(
                of: #""kind":"remoteTarget","project":"Remote.xcodeproj""#,
                with: #""kind":"remoteTarget","project":"Missing.xcodeproj""#)
            expected = "Remote dependency of App"
        case "imported-membership":
            document = referenceDocument.replacingOccurrences(
                of: "App/frameworks", with: "App/resources")
            expected = "Unknown or ambiguous build phase"
        case "package-phase":
            document = referenceDocument.replacingOccurrences(
                of: #""build-phase":{"build-phase":"frameworks"}"#,
                with: #""build-phase":{"build-phase":"resources"}"#)
            expected = "unknown or ambiguous package build phase"
        case "package-other-target-phase":
            document = referenceDocument.replacingOccurrences(
                of: #""build-phase":{"build-phase":"frameworks"}"#,
                with: #""build-phase":{"build-phase":"id:222222222222222222222222"}"#)
            expected = "unknown or ambiguous package build phase"
        default:
            let version = kind == "version" ? "Missing.xcdatamodel" : "id:BBBBBBBBBBBBBBBBBBBBBBBB"
            document = referenceDocument.replacingOccurrences(
                of: #""current-version":"V2.xcdatamodel""#,
                with: #""current-version":""# + version + #"""#)
            expected = "must name a child file"
        }
        expectFailure(containing: expected) {
            _ = try ProjectValidator.validate(data: Data(document.utf8))
        }
    }

    @Test func schemeCannotBeTheRootArtifact() throws {
        let raw = #"""
            {
              "protocolVersion":1,"schemaVersion":2,"kind":"scheme","rootArtifactId":"scheme",
              "paths":[{"id":"file","base":{"kind":"uri","uri":"file:///tmp"},"path":"Main.xcscheme","expectedKind":"any","mustExist":false,"context":"test"}],
              "artifacts":[
                {"id":"scheme","kind":"scheme","bundlePathId":"file","filePathId":"file"},
                {"id":"project","kind":"project","bundlePathId":"file","filePathId":"file"}
              ]
            }
            """#
        let manifest = try JSONDecoder().decode(InputManifest.self, from: Data(raw.utf8))
        expectFailure(containing: "Invalid root artifact") { try manifest.validate() }
    }
}
