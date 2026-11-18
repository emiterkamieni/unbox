# Code signing with SignPath Foundation

Windows releases are signed in [.github/workflows/windows.yml](../.github/workflows/windows.yml) with two
signing requests per release, both approved by hand in SignPath:

1. **binaries** – `unbox.exe`, `unbox.dll` and `UnboxKit.dll` for x64 and Arm, before Velopack packs them, so
   the installed app and every update package contain signed files.
2. **installers** – `unbox-win-x64-Setup.exe` and `unbox-win-arm64-Setup.exe`, after packing (the installers
   contain the packages, so they can only be signed afterwards).

Velopack's `Update.exe` and the .NET runtime come from other projects and are not signed with unbox's
certificate (the .NET files are already signed by Microsoft). The signing steps are skipped until the
repository variable `SIGNPATH_ORGANIZATION_ID` exists, so releases keep working unsigned before that.

## One-time setup

1. Turn on two-factor authentication for GitHub and, later, for SignPath (required by SignPath Foundation).
2. Apply at <https://signpath.org/apply>. Suggested answers:

   | Field | Answer |
   | --- | --- |
   | Project Name | unbox |
   | Repository URL | https://github.com/emiterkamieni/unbox |
   | Homepage URL | https://github.com/emiterkamieni/unbox |
   | Download URL | https://github.com/emiterkamieni/unbox/releases |
   | Privacy Policy URL | https://github.com/emiterkamieni/unbox#privacy |
   | Tagline | See what Box Drive keeps offline on your computer – and free the space with one click. |
   | Category | Productivity |
   | Description | unbox is a small menu bar (macOS) and notification area (Windows) app for Box Drive users. It lists every folder and file that Box Drive keeps available offline, with the disk space each one uses, and lets the user switch them back to online-only and free the space. It changes the same offline settings as Finder and File Explorer do (on Windows through the documented Cloud Files API), never writes to Box Drive's own files and collects no data. |
   | Reputation | (links showing that people use unbox: stars, download counts from the releases, posts or discussions) |
   | Maintainer Type | Individual maintainer(s) |
   | Build System | GitHub Actions |

3. After approval, in SignPath:
   - link the project **unbox** to the trusted build system *GitHub.com* and to this repository;
   - add two artifact configurations with the slugs **binaries** and **installers**, using
     [binaries.xml](artifact-configurations/binaries.xml) and
     [installers.xml](artifact-configurations/installers.xml);
   - create an API token for a CI user with the *submitter* role on the release signing policy.
4. In the GitHub repository (**Settings → Secrets and variables → Actions**):
   - secret `SIGNPATH_API_TOKEN` – the API token;
   - variable `SIGNPATH_ORGANIZATION_ID` – the SignPath organization ID;
   - optional variables `SIGNPATH_PROJECT_SLUG` (default `unbox`) and `SIGNPATH_SIGNING_POLICY_SLUG`
     (default `release-signing`).
5. Remove the note under *Code signing policy* in the README.

## Each release

`scripts/release.py X B --publish` pushes the tag; the workflow then waits up to an hour for each of the two
signing requests. Approve them in SignPath (it sends an e-mail), and the signed installers and packages are
added to the release together with their checksums.
