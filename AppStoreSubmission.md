# App Store Submission Checklist

## 1. Apple Developer Account
- [ ] Enroll in the **Apple Developer Program** ($99/year) at developer.apple.com
- [ ] For a Mac app, decide: Mac App Store or also iOS? (the app already has `#if os(macOS)` guards, so it's cross-platform)

## 2. App Store Connect Setup
- [ ] Create an **App Record** at appstoreconnect.apple.com
- [ ] Set a **Bundle ID** (e.g. `com.yourname.weeklymovies`) — register it in the Developer portal first
- [ ] Set **Version** (e.g. `1.0`) and **Build Number** in Xcode → Target → General

## 3. Required Metadata
- [ ] **App name**: "Weekly Movies" (check it's not already taken)
- [ ] **Subtitle** (30 chars max): e.g. "New Releases, Every Week"
- [ ] **Description** (4000 chars max)
- [ ] **Keywords** (100 chars): e.g. movies, releases, streaming, theater, TMDb
- [ ] **Category**: Entertainment (primary), possibly Reference (secondary)
- [ ] **Support URL**: a webpage or even a simple GitHub page works
- [ ] **Privacy Policy URL**: **required** since the app makes network requests — can be a simple page

## 4. Screenshots (Required)
For iPhone (if submitting iOS):
- [ ] 6.9" display (iPhone 16 Pro Max) — **required**
- [ ] 6.5" display (iPhone 14 Plus / 15 Plus) — required if supporting older devices

For iPad (if supporting iPad):
- [ ] 13" iPad Pro — required

For Mac (if submitting macOS):
- [ ] At least 1 screenshot at 1280×800 or larger

At least **3 screenshots** per device size. Take them in the Simulator via **Device → Screenshot** or `⌘S`.

## 5. App Icon
- [x] **1024×1024 PNG** — ✅ already done (clapperboard icon)
- Make sure it has **no alpha channel** (App Store rejects transparent icons)

## 6. Privacy Nutrition Labels
In App Store Connect → App Privacy, declare:
- [ ] **Network requests** to TMDb (api.themoviedb.org) → "Data Not Linked to You"
- [ ] **UserDefaults** (country code) → stored locally, no disclosure needed
- [ ] **Keychain** (TMDb API key) → stored locally, no disclosure needed
- The app doesn't collect analytics or personal data, so this should be straightforward

## 7. Xcode Build Steps
- [ ] Set **Deployment Target** (e.g. iOS 17.0+ given `@Observable` usage)
- [ ] Enable **Automatic Signing** with your Apple ID in Xcode → Signing & Capabilities
- [ ] Archive the app: **Product → Archive**
- [ ] Upload via the **Organizer** → Distribute App → App Store Connect

## 8. ⚠️ Biggest Risk: API Key Requirement
Apple reviewers will test the app cold. Since it requires a TMDb API key to show any content, they may **reject it** for not functioning out of the box. Options:

| Option | Pros | Cons |
|--------|------|-------|
| **Keep user-provided key** (current) | No cost, no backend | Reviewer must know to get a TMDb key — add clear onboarding |
| **Bundle a key** | Works immediately | Key is exposed in the binary; violates TMDb ToS if abused |
| **Build a small proxy backend** | Best UX, no key exposure | Extra work (Vercel/Cloudflare Worker would be free/cheap) |

The safest path with the current setup: make the **API key setup screen** very clear, with a direct link to https://www.themoviedb.org/settings/api and a note explaining it's free. Include that explanation in the **"Notes for Reviewer"** field in App Store Connect.
