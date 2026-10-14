# Swiftify

A native iPhone app for your own Spotify account, built with SwiftUI for iOS 26. Browse your library, search, control playback, read synced lyrics and manage playlists in an interface made for iPhone.

Swiftify is an independent hobby project. It is not affiliated with, endorsed by or sponsored by Spotify.

## What it is

Swiftify is a remote control and library browser for Spotify. It does not play music itself. Sound always comes from the official Spotify app or another Spotify Connect device such as a speaker, a computer or a TV. Swiftify controls it through the official Spotify Web API.

You build the app yourself, run it on your own iPhone and connect it with your own free Spotify developer app. There is no App Store release, no shared account and no server in between.

## Features

* Home with quick picks, recently played and your top artists
* Search with suggestions, history and a top result
* Library with sorting, grid layout, pinned playlists and Liked Songs
* Find in playlist, shuffle and a detail menu for playlists and albums
* Full player with dynamic background, queue sheet and device sheet with transfer and volume
* Synced lyrics with word by word highlighting
* Create playlists, play a link, join a Jam and build smart playlists from your top songs, recently played or Liked Songs
* Light and dark mode, accent colors, haptics and a minimizing tab bar
* Optional caching of song lists and cover art for a faster app
* Guided setup inside the app

## What you need

* An iPhone running iOS 26.1 or newer
* A Mac with Xcode 26.1 or newer
* An Apple ID, a free one is enough
* A Spotify Premium account
* The official Spotify app on your iPhone, or another Spotify Connect device, to play the sound

## Install on your iPhone

### 1. Get the code

```bash
git clone https://github.com/moritzwendt/swiftify.git
cd swiftify
open Swiftify.xcodeproj
```

### 2. Sign with your own account

In Xcode select the Swiftify target and open Signing and Capabilities.

1. Choose your Apple ID as Team. You can add it under Xcode, Settings, Accounts.
2. Change the Bundle Identifier to something unique, for example `com.yourname.swiftify`.

### 3. Run it

1. Connect your iPhone with a cable, unlock it and tap Trust.
2. On the iPhone turn on Developer Mode under Settings, Privacy and Security, Developer Mode. The phone restarts once.
3. Choose your iPhone as the run destination at the top of Xcode and press Run.
4. With a free Apple ID, open Settings, General, VPN and Device Management on the iPhone and trust your developer profile.

Builds signed with a free Apple ID expire after 7 days. Press Run again to renew it. A paid Apple Developer Program membership keeps the app for a year.

## Connect Spotify

Swiftify walks you through this on first launch, so you can follow the screens. In short:

1. Open the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and log in with your Premium account.
2. Create an app. Name and description can be anything.
3. Add the Redirect URI `swiftify://callback` and tick Web API.
4. Save, open the app Settings and copy the Client ID.
5. Paste the Client ID into Swiftify and tap Sign in with Spotify.

Every person uses their own Client ID. Swiftify does not ship with a key and never shares one.

## Spotify limits

Spotify decides how developer apps work and changes the rules from time to time.

* The owner of a developer app needs Spotify Premium.
* Apps in development mode are limited to a very small group of users, which is plenty for personal use.
* If you sign in with a different Spotify account than the one that owns the developer app, add that account under User Management in the dashboard.

## Privacy

* Swiftify has no server of its own and contains no analytics, advertising or tracking.
* Your Client ID and settings are stored on your device. Spotify tokens are stored in the iOS Keychain.
* Song lists and cover art can be cached temporarily on your device. You can turn this off and clear it under Settings, Cache.
* Signing out deletes the stored tokens and clears these caches. Deleting the app removes everything else.
* Network requests go to Spotify for login, library data and artwork, and to [LRCLIB](https://lrclib.net) for lyrics. For lyrics, the song title, artist, album and duration are sent.

## Legal

* Spotify and the Spotify logo are trademarks of Spotify AB. Apple, iPhone, iOS and Xcode are trademarks of Apple Inc. All other names belong to their owners. They are used only to describe what Swiftify works with.
* Swiftify is made for private, non-commercial use with your own account and your own developer app. By using it you also agree to the [Spotify Developer Terms](https://developer.spotify.com/terms) and the [Spotify Developer Policy](https://developer.spotify.com/policy), which apply to your Client ID.
* Swiftify does not stream, download, record or copy music. Playback happens in official Spotify clients. The Mark as downloaded option is a private label inside Swiftify and does not store any audio.
* Metadata and cover art come from Spotify and belong to their respective owners.
* Lyrics come from the community database LRCLIB, which is not affiliated with Swiftify. Lyrics may be protected by copyright. Swiftify only shows them while you listen and keeps the lyrics of recently played songs in memory.
* Please do not upload builds of Swiftify to TestFlight or the App Store, and do not share your Client ID. Spotify limits development mode apps and requires its own review for anything beyond that.
* If you represent a rights holder and have a concern, please open an issue.

## Disclaimer

Swiftify is provided as is, without warranty of any kind. Use it at your own risk, including any action Spotify may take regarding your developer app or account. Spotify can change or restrict its API at any time, which may break features of the app. To the extent permitted by law, the author is not liable for any damages arising from the use of this software. This is not legal advice.

## Troubleshooting

**Sign in fails with INVALID_CLIENT.**
The Client ID is wrong. It is 32 letters and numbers and is shown in your app Settings in the dashboard.

**Sign in fails with a redirect error.**
The Redirect URI in the dashboard must be exactly `swiftify://callback`. Tap Add after pasting it, then Save.

**Sign in works but nothing loads.**
Make sure the account that owns the developer app has Premium and that the account you sign in with is listed under User Management.

**Nothing plays or no device is found.**
Open the Spotify app on your iPhone, start any song once and come back to Swiftify.

**The app stopped opening after a week.**
That is the limit of a free Apple ID. Connect the iPhone and press Run in Xcode again.

## For developers

* Pure SwiftUI with no third party dependencies
* Talks to the Spotify Web API with the authorization code flow and PKCE
* The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After running `xcodegen`, set your own team again.
* Launch with the argument `-sample` to explore the interface with sample data and without signing in

Source folders in `Sources`: `API`, `App`, `Auth`, `Cache`, `Library`, `Lyrics`, `Models`, `Onboarding`, `Player`, `Queue`, `Settings`, `UI`.
