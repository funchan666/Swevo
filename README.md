# Swevo

Swevo is a native SwiftUI video-file workspace. Open a video from Files or Photos, play or scrub through the local copy, and apply trim, speed, crop, rotation, mirroring or audio changes. Video and audio exports appear under Files → Exports and can be shared or saved to the Files app. The Videos tab shows recently opened local videos and offline downloads. Lesson links, short codes, tutorials and camera practice are under Videos → Lesson link or code.

Open `Swevo.xcodeproj` and select the shared `Swevo` scheme. The minimum deployment target is iOS 17. The Duo layout paths use the iOS 27.1 SDK, which is available in Xcode 27.1.

## Test configuration

- API host `devapi.io-jp.com` and `getV2.name` `Swevo`.
- Bundle ID `im.seex.lobo` in `Config/Swevo.xcconfig`. The guest login source and business package name derive from the same setting. These test apps share a Bundle ID, so install them one at a time.
- Google iOS demo App ID, app-open and rewarded units. Membership requests `coins_1.99` monthly (USD 9.99) and `conis_4.99` yearly (USD 99.99) in Apple Sandbox. The app displays the prices returned by StoreKit.
- Website, terms and privacy point to HTTPS placeholders.

For playback integration, open Videos → Lesson link or code and enter the Clipo test short code from the Toolkit. Verify that the search result opens in the full-screen player. Use a new or authorized test account when verifying Apple purchases and restores.

## Playback and app-open diagnostics

- In Console, filter `app.swevo` by `API`, `LessonFeed` and `Playback`. Check the `search-check` response and whether it provides an HLS or direct-file URL. For playback failures, the player logs the source type and error codes. On iOS 27 or later it also logs the media response code when available.
- For app-open ads, filter by `AppOpen`. Check eligibility and the reason the opportunity ended, then look for the inventory result, impression, dismissal or presentation failure. The interval timestamp is recorded on an impression. A consumed ad is replaced for a later opportunity.

## Production transition

After test acceptance, update the Bundle ID, API domain, AdMob configuration, official links and registered membership mapping for this app. The release configuration name stays `Swevo`. Check backend registration, receipt routing and signing against the effective build settings.

## Verification

Source, project settings and asset references were reviewed. Builds, live backend calls, playback, ad impressions, Apple transactions and iPhone Duo device behavior remain to be verified.
