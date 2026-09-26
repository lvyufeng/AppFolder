import AppFolderKit
import Foundation

/// Prints the `LSApplicationQueriesSchemes` array for `Config/AppFolder-Info.plist`.
///
/// The catalog in `AppCatalog+Data.swift` and the app's `Info.plist` have to
/// agree: a scheme missing from the plist makes `canOpenURL` answer `false` even
/// when the app is installed, which looks exactly like "the app isn't there".
/// Rather than keep two lists in sync by hand, run this and paste:
///
///     swift run --package-path Packages/AppFolderKit appfolder-schemes
///
/// Pass `--check` to exit non-zero when the plist is stale, which is what CI
/// should use.
@main
struct GenerateQueriedSchemes {
    static func main() {
        let schemes = AppCatalog.queriedSchemes
        let check = CommandLine.arguments.contains("--check")

        if check {
            guard let plist = try? String(contentsOf: plistURL, encoding: .utf8) else {
                FileHandle.standardError.write(Data("cannot read \(plistURL.path)\n".utf8))
                exit(1)
            }
            // The plist takes bare scheme names (`weixin`); the catalog stores
            // launchable URLs (`weixin://`). Compare on the bare form.
            let missing = schemes.filter { !plist.contains("<string>\(bare($0))</string>") }
            guard missing.isEmpty else {
                FileHandle.standardError.write(Data("""
                AppFolder-Info.plist is missing \(missing.count) scheme(s):
                \(missing.joined(separator: "\n"))

                Run: swift run --package-path Packages/AppFolderKit appfolder-schemes

                """.utf8))
                exit(1)
            }
            print("Info.plist is up to date (\(schemes.count) schemes).")
            return
        }

        for scheme in schemes {
            print("\t\t<string>\(bare(scheme))</string>")
        }
    }

    private static func bare(_ scheme: String) -> String {
        scheme.replacingOccurrences(of: "://", with: "")
    }

    private static var plistURL: URL {
        // Package builds put the CWD at the package directory; the plist lives
        // two levels up from Packages/AppFolderKit.
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "../../Config/AppFolder-Info.plist")
            .standardizedFileURL
    }
}
