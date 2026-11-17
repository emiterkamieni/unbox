#!/usr/bin/env python3
"""Builds, signs and (optionally) publishes an unbox release.

    scripts/release.py 1.0.1 2               # build into dist/ only
    scripts/release.py 1.0.1 2 --publish     # also tag and create the GitHub release

VERSION is the displayed version, BUILD the monotonic CFBundleVersion Sparkle compares.
Release notes are read from release-notes/<VERSION>.md.

The ZIP is signed with the Sparkle EdDSA key from $UNBOX_SPARKLE_KEY, or
~/.config/unbox/sparkle_private_key, or the "unbox-Releases" Keychain account.
The signature is checked against SUPublicEDKey before anything is written to dist/.
"""
import argparse
import email.utils
import hashlib
import html
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "emiterkamieni/unbox"
INFO_PLIST = ROOT / "Support" / "Info.plist"
DIST = ROOT / "dist"
KEY_ACCOUNT = "unbox-Releases"


def run(*command, capture=False, cwd=ROOT):
    result = subprocess.run([str(part) for part in command], cwd=cwd, check=True,
                            stdout=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None


def set_version(version, build):
    with INFO_PLIST.open("rb") as handle:
        info = plistlib.load(handle)
    previous = int(info["CFBundleVersion"])
    if build < previous:
        sys.exit(f"BUILD {build} is lower than the current CFBundleVersion {previous}")
    if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (version, str(build)):
        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = str(build)
        with INFO_PLIST.open("wb") as handle:
            plistlib.dump(info, handle)
    return info


def sign(archive, sparkle_bin):
    key_file = Path(os.environ.get("UNBOX_SPARKLE_KEY", Path.home() / ".config/unbox/sparkle_private_key"))
    if key_file.exists():
        return run(sparkle_bin / "sign_update", "--ed-key-file", key_file, "-p", archive, capture=True)
    return run(sparkle_bin / "sign_update", "--account", KEY_ACCOUNT, "-p", archive, capture=True)


def verify(archive, signature, public_key):
    """Independent check with CryptoKit, so a wrong key can never reach users."""
    script = f"""
import CryptoKit
import Foundation
let key = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "{public_key}")!)
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
exit(key.isValidSignature(Data(base64Encoded: "{signature}")!, for: data) ? 0 : 1)
"""
    source = ROOT / ".build" / "verify-signature.swift"
    binary = source.with_suffix("")
    source.parent.mkdir(exist_ok=True)
    source.write_text(script)
    run("swiftc", "-O", "-o", binary, source)
    if subprocess.run([str(binary), str(archive)], cwd=ROOT).returncode != 0:
        sys.exit("The EdDSA signature does not match SUPublicEDKey – release aborted.")


def notes_html(markdown):
    """Release notes for Sparkle's window: paragraphs, bullet lists and **bold**."""
    blocks, items = [], []

    def inline(text):
        text = html.escape(text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
        return re.sub(r"`(.+?)`", r"<code>\1</code>", text)

    def flush():
        if items:
            blocks.append("<ul>" + "".join(f"<li>{inline(item)}</li>" for item in items) + "</ul>")
            items.clear()

    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith(("- ", "* ")):
            items.append(stripped[2:])
        elif not stripped or stripped.startswith("#"):
            flush()
            if stripped.startswith("#"):
                blocks.append(f"<h3>{inline(stripped.lstrip('#').strip())}</h3>")
        else:
            flush()
            blocks.append(f"<p>{inline(stripped)}</p>")
    flush()
    return "\n".join(blocks)


def appcast(version, build, minimum_system, url, length, signature, notes):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>unbox</title>
    <link>https://github.com/{REPOSITORY}</link>
    <item>
      <title>unbox {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum_system}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/{REPOSITORY}/releases/tag/v{version}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
{notes}
      ]]></description>
      <enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version")
    parser.add_argument("build", type=int)
    parser.add_argument("--publish", action="store_true", help="tag the commit and create the GitHub release")
    args = parser.parse_args()

    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        sys.exit("VERSION must look like 1.2.3")
    notes_file = ROOT / "release-notes" / f"{args.version}.md"
    if not notes_file.exists():
        sys.exit(f"Missing release notes: {notes_file.relative_to(ROOT)}")

    info = set_version(args.version, args.build)
    if args.publish and run("git", "status", "--porcelain", capture=True):
        sys.exit("Commit the version bump and all changes before publishing.")

    sparkle_bin = Path(run(ROOT / "scripts" / "sparkle.sh", capture=True)) / "bin"
    run(ROOT / "scripts" / "build.sh")

    DIST.mkdir(exist_ok=True)
    name = f"unbox-{args.version}-macos-arm64.zip"
    archive = DIST / name
    archive.unlink(missing_ok=True)
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", ROOT / "build" / "unbox.app", archive)

    signature = sign(archive, sparkle_bin)
    verify(archive, signature, info["SUPublicEDKey"])

    url = f"https://github.com/{REPOSITORY}/releases/download/v{args.version}/{name}"
    feed = DIST / "appcast.xml"
    feed.write_text(appcast(args.version, args.build, info["LSMinimumSystemVersion"], url,
                            archive.stat().st_size, signature, notes_html(notes_file.read_text())), encoding="utf-8")
    sums = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in (archive, feed))
    (DIST / "SHA256SUMS").write_text(sums)
    print(f"Signed release in {DIST.relative_to(ROOT)}/: {name}, appcast.xml, SHA256SUMS")

    if args.publish:
        tag = f"v{args.version}"
        run("git", "tag", "-a", tag, "-m", f"unbox {args.version}")
        run("git", "push", "origin", tag)
        run("gh", "release", "create", tag, archive, feed, DIST / "SHA256SUMS", "--repo", REPOSITORY,
            "--verify-tag", "--title", f"unbox {args.version}", "--notes-file", notes_file)
        print(f"Published https://github.com/{REPOSITORY}/releases/tag/{tag}")


if __name__ == "__main__":
    main()
