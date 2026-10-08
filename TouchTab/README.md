# Touch-Tab

## 3E distribution

This independent app now lives in `TouchTab/` in [Ezodis/3E](https://github.com/Ezodis/3E). Download `TouchTab.zip` from a `touchtab-v…` [release](https://github.com/Ezodis/3E/releases), or get both apps in the bundle archive. Install this app as `/Applications/Touch-Tab.app`. Its update menu checks only TouchTab releases in 3E.

Source imported from Ezodis/Touch-Tab commit `747110641062ebf9933cc12e1c6ce1a06feecb29`. The original upstream README follows for attribution and gesture instructions; its upstream download links are not this fork's update feed.

### Build this version

From the repository root, run `zsh TouchTab/build.sh`. Xcode 27 builds require macOS 12 or newer; the output is a universal Intel/Apple Silicon app in `build/TouchTab/Build/Products/Release/Touch-Tab.app`. By default it is ad-hoc signed; provide `TOUCHTAB_SIGNING_IDENTITY` to use your own persistent signing identity. App Sandbox remains enabled. Local development signing is not Developer ID notarization: other Macs may require manual approval.

Give this app Accessibility access in System Settings before testing gestures. Four-finger left/right switches apps; a force-click switches windows in the current app. macOS trackpad shortcuts can compete with these gestures; change them only if you encounter a conflict. Quit releases the gesture tap and any in-progress app-switching modifier.

![Touch-Tab AppSwitcher](https://user-images.githubusercontent.com/511242/185958284-e0f962aa-3f88-4d95-9176-3f3fe49a24c8.gif)

Switch apps with trackpad on macOS.
Use 4-finger gestures for app switching, copy, and paste operations.

Want to support? [Buy me a coffee](https://www.buymeacoffee.com/ris58h).

## Installation
1. Download the [latest](https://github.com/ris58h/Touch-Tab/releases/latest/download/Touch-Tab.zip) `Touch-Tab.zip` from [Releases](https://github.com/ris58h/Touch-Tab/releases) page.
2. Unzip the archive and move `Touch-Tab.app` into the `Applications` folder.
3. The app is ad-hoc signed so when you run the app macOS will warn you: `"Touch-Tab" can’t be opened because Apple cannot check it for malicious software`. Right-click the app and click `Open`, a 
pop-up will appear, click `Open` again.
4. The app needs access to global trackpad events. Allow Touch-Tab to control your computer in `System Settings > Privacy & Security > Accesibility`. If you had Touch-Tab installed before you may need to remove Touch-Tab from the `Accessibility` list first and add it again.
5. Disable 3-finger swipe between full-screen apps or make it 4-finger in `System Settings > Trackpad > More Gestures > Swipe between full-screen apps` to avoid conflicts with Touch-Tab's 4-finger gestures.

## Usage
- **4-finger swipe right or left**: Switch between apps
  - Hold after the swipe or swipe slowly to show App Switcher UI
  - Pro tip: you can use 2-finger scroll to switch apps in App Switcher faster
- **4-finger pinch in**: Copy (⌘C)
- **4-finger pinch out**: Paste (⌘V)

### Hide Status Bar Item
Holding ⌘ drag the item away from the status bar until you see ✖️ (cross icon) then let it go. To recover the item just open the app one more time.

## Troubleshooting
### "Touch-Tab" can’t be opened because Apple cannot check it for malicious software
Right-click the app and click `Open`, a pop-up will appear, click `Open` again.
### It's running but doesn't work
- Check that Touch-Tab is allowed to control your computer in `System Settings > Privacy & Security > Accesibility`.  If you had Touch-Tab installed before you may need to remove Touch-Tab from the `Accessibility` list first and add it again.
- Check that 3-finger swipe is disabled in `System Settings > Trackpad > More Gestures > Swipe between full-screen apps`.
### 3-finger or 4-finger swipe scrolls content instead
It's a [known issue](https://github.com/ris58h/Touch-Tab/issues/1). The workaround is to setup `Mission Control` or `App Expose` to use 3-finger swipe in `System Settings > Trackpad > More Gestures`.
### It still doesn't work
Please create an [issue](https://github.com/ris58h/Touch-Tab/issues).
