# Penguin Slide for iOS

A playful SwiftUI / SceneKit penguin jumping game for iPhone and iPad.
Includes the icy stage, animal characters, picture quizzes, sound effects and speech.

## Build

Open `HelloFlight.xcodeproj` and select the `HelloFlight` scheme. The minimum deployment target is iOS 18. The internal project name and bundle identifier are retained for compatibility with the existing TestFlight app.

For an unsigned archive on a Mac with Xcode installed:

```sh
bash ci/build-unsigned.sh
```

The **Build iOS** workflow is manual only. No macOS jobs run automatically on pushes or pull requests. This source snapshot does not include the earlier prototype apps or their tests.

## Release signing

The manual **Upload to TestFlight** workflow reads existing encrypted signing assets from a separate private repository. The owner must configure its protected environment before use; no Apple credentials or signing material are committed here. See [release setup](docs/RELEASING.md).

## Assets and licensing

The bundled BIZ UDPGothic font is distributed under the SIL Open Font License; its notice is in `HelloFlight/Fonts/FontLicenses.txt`. No general license is granted for the source or other assets. Asset redistribution approval must be checked before making this repository public. See [asset review](docs/ASSETS.md).
