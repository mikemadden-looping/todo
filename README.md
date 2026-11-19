# To-Do

A replacement for Microsoft To Do on iPhone, iPad and Mac, built to work and
look like it:

- **My Day** (resets each day, with the lightbulb suggestions), **Important**,
  **Planned** (grouped Earlier / Today / Tomorrow / This week / Later),
  **Tasks**, plus optional **All** and **Completed** smart lists
- Your own lists, with color or scene themes, a leading emoji as the list
  icon, and **groups** of lists
- Tasks with **steps**, **notes**, **due dates**, **reminders** (notifications
  with a "Mark as completed" button) and **repeats** (daily, weekdays,
  weekly on chosen days, monthly, yearly, every N…). Completing a repeating
  task creates the next one, like To Do.
- Star to mark important, swipe to add to My Day or delete, drag to reorder,
  sort by importance / due date / My Day / alphabetically / creation date,
  collapsible Completed section, search, completion sound
- **iCloud sync** between your devices, and **shared lists** with other
  iCloud users (the person button on a list)
- **Import from Microsoft To Do** (Settings → Import), which copies lists,
  tasks, steps, notes, dates, reminders and repeats

Data lives in Core Data synced by CloudKit (`NSPersistentCloudKitContainer`)
with a private store and a shared store, so there's no server to run.

## Setup

Uses the same signing secrets as the Trio Browser Build, set on the
`mikemadden-looping` organization: `TEAMID`, `GH_PAT`, `FASTLANE_KEY_ID`,
`FASTLANE_ISSUER_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, plus the existing
`Match-Secrets` repository. Below, `TEAMID` means your 10-character Apple
team ID.

### 1. Register the app

1. **Actions → 1. Add identifier → Run workflow.** Registers
   `com.TEAMID.todo` with iCloud and Push Notifications turned on.
2. On [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list/cloudContainer)
   → Certificates, Identifiers & Profiles → **Identifiers**, switch the filter
   (top right) to **iCloud Containers**, click **+**, and create
   `iCloud.com.TEAMID.todo` (any description).
3. Switch the filter back to **App IDs**, open `com.TEAMID.todo`, check that
   **iCloud** is ticked, click its **Configure** (or Edit) button, tick the
   `iCloud.com.TEAMID.todo` container, Continue, **Save**.
4. **Actions → 1. Add identifier → Run workflow** again, so the provisioning
   profile includes the container.
5. **App Store Connect → Apps → + → New App.** Platform iOS, name e.g.
   "To-Do", bundle ID `com.TEAMID.todo`, any SKU.

### 2. One-time iCloud setup (needs Xcode, once)

TestFlight builds use CloudKit's Production environment, which only accepts
data whose record types have been deployed there. Apple's way to create them
is to run a Debug build once:

1. On the Mac: `brew install xcodegen`, then in this repo `xcodegen generate`
   and open `ToDo.xcodeproj`.
2. Select the **ToDo** target → Signing & Capabilities → pick your team. The
   bundle ID becomes `com.TEAMID.todo` automatically.
3. Pick **My Mac (Designed for iPad)** (or your plugged-in iPhone) and press
   Run. The scheme sets `INIT_CLOUDKIT_SCHEMA=1`, so on launch the app creates
   the record types in the Development environment. You need to be signed in
   to iCloud. Quit it after a few seconds.
4. Open the [CloudKit Console](https://icloud.developer.apple.com/) → your
   `iCloud.com.TEAMID.todo` container → **Schema** → check that record types
   `CD_TaskList`, `CD_TodoTask`, `CD_TaskStep` and `CD_ListGroup` are there →
   **Deploy Schema Changes…** → Deploy to Production.

If the data model ever changes, repeat steps 3–4.

### 3. Build to TestFlight

1. **Actions → 2. Build to TestFlight → Run workflow.** About 10 minutes, then
   Apple takes a few more to process it. It also rebuilds every Sunday so the
   build doesn't hit TestFlight's 90-day expiry.
2. App Store Connect → the app → **TestFlight**: add yourself and your wife to
   an internal testing group (each needs to be a user on your App Store
   Connect team), or use an external group with a public link. Install from the
   TestFlight app on iPhone, iPad and Mac.

**0. Check build** compiles on every push without signing.

### 4. Microsoft To Do import (optional)

The import signs in to Microsoft Graph, which needs an app registration:

1. Go to [entra.microsoft.com](https://entra.microsoft.com) → **App
   registrations → New registration**. Signing in with a personal Microsoft
   account may ask you to create a free Azure account first.
2. Name: anything (e.g. "To-Do import"). Supported account types: **Accounts
   in any organizational directory and personal Microsoft accounts**.
3. Redirect URI: platform **Public client/native (mobile & desktop)**, URI
   `todoimport://auth`. Register.
4. Copy the **Application (client) ID**. Either add it as a repository
   **variable** (Settings → Secrets and variables → Actions → Variables) named
   `MS_CLIENT_ID` and rebuild, or paste it into the app's import screen.
5. Under **API permissions**, `User.Read` is there by default; add Microsoft
   Graph → Delegated → **Tasks.Read**. No admin consent is needed for personal
   accounts.

Then in the app: Settings (tap your name at the top) → **Import from
Microsoft To Do** → Sign in and import. Your wife signs in with her own
Microsoft account on her phone. Running it again skips tasks it already
imported. My Day membership and file attachments aren't available through the
API, so they don't come over.

## Sharing a list

Open a list → the person button (top right) → choose how to send the
invitation. The other person taps the link to join; the list then shows up in
their app with a people icon. They can add, complete and edit tasks. To stop
sharing, the owner opens the same button → Stop Sharing; someone you shared
with can use **Leave list** in the list's ⋯ menu.

## Notes

- Reminders are local notifications, rescheduled on each device as tasks sync,
  so each device needs notification permission (asked when you first set one).
- Themes and sort order for the smart lists are per device; for your own
  lists they sync (and are shared with people you share the list with).
