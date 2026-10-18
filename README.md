# W

A little space to focus. A native, open-source macOS menu-bar app that connects what you're working on to your Notion tasks.

**Early developer preview.** No AI account or paid model API required. macOS 14+, Swift 6 toolchain. Source is MIT licensed.

## Run

```sh
swift test
./scripts/build-app.sh
open dist/W.app
```

Use the app bundle rather than `swift run` for microphone permissions and notifications. The build script uses an ad-hoc signature by default. It builds for your Mac's architecture. Distribution to other people still requires Developer ID signing and Apple notarization; CI artifacts are development builds, not notarized releases.

Press **Shift–Command–W** or click **W** in the menu bar. Type or dictate, select a match, and start. Drag the panel anywhere or use its dock button to return it to the top of the current display. Escape hides it. The first preview uses a fixed shortcut.

## Notion setup

1. Create an internal Notion integration with read, insert, and update content capabilities. Grant it access to your tasks and (optionally) projects databases.
2. Open W Settings and enter the integration token. W stores it in macOS Keychain, never in this repository or its JSON state file.
3. Enter the **data source ID**, not the database ID or a view ID. For a database ID, retrieve `GET /v1/databases/{database_id}` with your integration to find its `data_sources` IDs. See [Notion's data source guide](https://developers.notion.com/docs/upgrade-guide-2025-09-03).
4. Map the title, status/select, project relation, and optional start-date properties by their exact names. Choose existing in-progress and done values.
5. Click **Connect / refresh tasks**. W validates the schema before indexing tasks. It never adds properties or status options for you.

Notion API version: `2025-09-03`. One task data source and one optional project data source per install. Project relations must target the selected project data source. Use a test database for initial end-to-end validation.

## What works

- Native floating, dark panel and system-wide shortcut.
- On-device speech transcription when supported by your language/device; typing always works. W does not fall back silently to cloud audio processing.
- Local keyword/fuzzy matching across titles and project names. Completed tasks are excluded. Every match requires selection; unmatched input never creates a task automatically.
- Explicit task creation with an editable title and optional chosen project. Without Notion configured, tasks stay local.
- Exact elapsed time, pause/resume, Done, Stop for now, 25-minute check-ins, and 5/10/15-minute extensions.
- Session history and ordered, durable Notion status-update queue. Failed updates remain pending with a visible Retry action. Notion updates run when you start/finish, reconnect, or retry; there is no silent background retry loop.
- Sleep pauses tracking. Recovery after a crash uses the last saved heartbeat and requires Resume.

## Data and behavior

State lives at `~/Library/Application Support/W/state.json`. It includes cached task/project names, session timestamps, and pending updates. It is local, unencrypted app data protected by your macOS account. No analytics or hosted backend. Notion credentials go only to the Notion API. Task matching never sends data to an LLM.

One task can have multiple sessions. Done completes the Notion task; Stop for now ends the session without completing it. Pausing does not change the task's Notion status. The optional Notion start-date field records the latest session start. Full session history and elapsed totals currently remain local; a separate Notion sessions database is not implemented.

Creation requests are never automatically retried because a lost network response may hide a successful creation. After a creation error, refresh and search Notion before retrying. Status patches are safely replayable but may overwrite a concurrent external status edit; review pending updates before Retry. Switching workspaces while updates are pending is not supported.

## Repository

- `Sources/WCore`: matching, session model, Notion client.
- `Sources/W`: SwiftUI/AppKit panel, speech, Keychain, persistence.
- `Tests/WCoreTests`: matching, timing, and persistence tests.
- `scripts/build-app.sh`: builds a runnable `.app` bundle.
- `website`: static landing page ready for a later Vercel deployment.

Vercel hosts the website, not the native Mac executable. Import this repository with Framework Preset **Other** and output directory `website`; the root `vercel.json` also specifies it. No deployment is required to run W locally.

## Before a public binary release

- Validate against a disposable Notion database: read, create, start date, pause/resume, done, offline retry, permissions failure.
- Exercise dictation permissions, notification delivery, multiple displays, and sleep/wake on real Macs.
- Add signed/notarized arm64 and x86_64 release artifacts and a stable update channel.
- Improve onboarding with property pickers and public OAuth (requires a secure token-exchange service), configurable hotkeys, and explicit sync-conflict resolution.

No shared integration secret belongs in a distributed desktop binary. Contributors should use their own test integration and never commit tokens, local state, or private task fixtures.

### CI setup

The workflow template is at `scripts/ci.yml.example`. Move it to `.github/workflows/ci.yml` to enable macOS build/test artifacts. The initial publishing credential lacks GitHub's `workflow` scope, so automatic CI is not enabled yet.
