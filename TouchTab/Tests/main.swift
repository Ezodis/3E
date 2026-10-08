import Foundation

func fixture(_ tag: String) -> [String: Any] {
    ["tag_name": tag, "draft": false, "prerelease": false,
     "assets": [["name": "TouchTab.zip", "browser_download_url": "https://github.com/Ezodis/3E/releases/download/\(tag)/TouchTab.zip"]]]
}
assert(AppReleaseUpdates.newest([fixture("touchtab-v1.5.1")])?.version == "1.5.1")
assert(AppReleaseUpdates.newest([fixture("touchbar-v9.9.9"), fixture("bundle-v9.9.9")]) == nil)
assert(AppReleaseUpdates.newest([fixture("touchtab-v1.9.0"), fixture("touchtab-v1.10.0")])?.version == "1.10.0")
var draft = fixture("touchtab-v9.9.9"); draft["draft"] = true
assert(AppReleaseUpdates.newest([draft]) == nil)
draft["draft"] = false; draft["prerelease"] = true
assert(AppReleaseUpdates.newest([draft]) == nil)
var wrong = fixture("touchtab-v1.5.1")
wrong["assets"] = [["name": "TouchTab.zip", "browser_download_url": "https://example.com/TouchTab.zip"]]
assert(AppReleaseUpdates.newest([wrong]) == nil)
assert(AppReleaseUpdates.newest([fixture("touchtab-v../bad")]) == nil)
assert(AppReleaseUpdates.newest(["bad": "response"]) == nil)
print("Passed independent TouchTab release validation. No network, gesture or UI actions.")
