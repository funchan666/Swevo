# Kstep

Kstep is a native SwiftUI video-file workspace. Open a video from Files or Photos, play or scrub through the local copy, and apply trim, speed, crop, rotation, mirroring or audio changes. Video and audio exports appear under **Videos → View files → Exports** and can be shared or saved to the Files app. Use **Video URL** on the Videos tab for shared videos. The third tab, **Camera moves**, is home to video browsing, camera examples, shot planning, and practice records. The last opened video has a larger preview and earlier entries appear in **Video history**. Existing link visits remain available under **Link history**.

To try the local review workflow, open **Tools → Mark a range** or import a recording from the results of a camera practice session. Set the start and end, then tap **Save range**. A saved range can be looped, applied to trim, or opened in **Compare frames** to inspect the start, middle and end stills. With Plus, tap **Share comparison image** in the comparison view or select a saved range under the same heading in the session results. The exported JPEG includes the range name and the timestamp of each still. **Export JPEG stills** shares the three separate images.

Open `Swevo.xcodeproj` and select the shared `kstep` scheme for the `Kstep` app target. The minimum deployment target is iOS 17. The Duo layout paths use the iOS 27.1 SDK, which is available in Xcode 27.1.

## Service configuration

- The API host is `o4r8xgd.kstep.site` and `getV2.name` is `Swevo`.
- `Config/Swevo.xcconfig` uses the shared test Bundle ID `im.seex.lobo` pending selection of Kstep’s Bundle ID. The guest login source and business package name derive from it.
- AdMob uses the packaged App ID in `Config/Swevo.xcconfig`. App-open and rewarded units come from `getV2.adList` as Google types `1` and `5` respectively. Each placement's `config.appId` must match the packaged App ID.
- Membership uses the test product IDs `coins_1.99` and `conis_4.99`. StoreKit supplies the prices and billing periods displayed in the app. Filter the Xcode console by `StoreKitPlans` for a missing or invalid product response.
- The app links to the [Kstep website](https://www.kstep.site), [privacy policy](https://www.kstep.site/privacy.html), and [terms](https://www.kstep.site/terms.html).

For playback verification, enter a supported video link or short code from the configured API. Check the full-screen player and the entry under Recently opened. Use an authorized test account when verifying Apple purchases and restores.

## Playback and app-open diagnostics

- In Console, filter `app.swevo` by `API`, `LessonFeed` and `Playback`. Check the `search-check` response and whether it provides an HLS or direct-file URL. For playback failures, the player logs the source type and error codes. On iOS 27 or later it also logs the media response code when available.
- For app-open ads, filter by `AppOpen`. Check eligibility and the reason the opportunity ended, then look for the inventory result, impression, dismissal or presentation failure. The interval timestamp is recorded on an impression. A consumed ad is replaced for a later opportunity.
- For UMP, filter by `AdPrivacy`. The app refreshes consent on launch with a publisher AdMob App ID. When UMP requires an entry point, open **Settings → Privacy & terms → Advertising privacy** from the fourth tab.

## Production transition

Debug and Release both inherit `Config/Swevo.xcconfig`. Once the Bundle ID is selected, use it for the signed app and the backend package registration. Verify the StoreKit products for that app and confirm that its backend recognizes Apple Sandbox transactions during App Review.

In AdMob **Privacy & messaging**, publish the messages for the regions you serve and assign them to the iOS app matching the packaged AdMob App ID. Use Kstep's privacy policy URL in the AdMob message and verify consent and placements with Google test devices. [Google iOS UMP setup](https://developers.google.com/admob/ios/privacy)

See the [App Review source audit](docs/AppReview/2026-11-16/review-report.md) for cross-device purchase restoration, guest account deletion, and submission evidence.

## Verification

Source, project settings and asset references were reviewed. Builds, live backend calls, playback, ad impressions, Apple transactions and iPhone Duo device behavior remain to be verified.
