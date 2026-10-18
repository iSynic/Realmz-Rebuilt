"""Validate the signed tablet preview's packaged inputs and Android manifest receipt."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


def verify(apk: Path, manifest_path: Path, signature_path: Path) -> dict:
    root = Path(__file__).resolve().parent.parent
    manifest = manifest_path.read_text(encoding="utf-8-sig")
    signature = signature_path.read_text(encoding="utf-8-sig")
    assert 'package="org.realmz.rebuilt.preview"' in manifest, "Wrong Android application ID"
    assert re.search(r'android:allowBackup[^\n]*0x0', manifest), "Cloud backup must be disabled"
    assert re.search(r'android:minSdkVersion[^\n]*0x18', manifest), "Unexpected template minimum SDK"
    assert re.search(r'android:targetSdkVersion[^\n]*0x24', manifest), "Unexpected template target SDK"
    assert not re.search(r'android:debuggable[^\n]*0xffffffff', manifest), "Preview must be a release build"
    permissions = re.findall(r'android:name[^\n]*="(android.permission.[^"]+)"', manifest)
    assert not permissions, f"Unexpected Android permissions: {permissions}"
    assert "Verified using v2 scheme (APK Signature Scheme v2): true" in signature
    certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})', signature)
    assert certificate, "Missing verified signing certificate"
    pinned = [root / 'src/storage/packages/application/realmz-classic-application-library.realmz2']
    campaigns = sorted((root / 'src/storage/packages/bundled_campaigns').glob('*.realmz2'))
    assert len(campaigns) == 13, "Expected exactly thirteen bundled campaigns"
    pinned += campaigns
    pinned += [root / p for p in ('src/storage/characters/realmz-classic-starter-characters.json',
                                'src/storage/characters/character-rule-recovery.json',
                                'LICENSE', 'THIRD_PARTY_NOTICES.txt')]
    hashes = {}
    with zipfile.ZipFile(apk) as archive:
        assert archive.testzip() is None, "APK ZIP CRC failure"
        names = archive.namelist()
        for name in names:
            assert 'AGENTS.md' not in name
            assert not re.match(r'assets/(tests|tools|docs|artifacts|addons|importer|music-importer)/', name), name
            if name.startswith('assets/'):
                assert archive.getinfo(name).compress_type == zipfile.ZIP_STORED, name
        abis = sorted({name.split('/')[1] for name in names if name.startswith('lib/')})
        assert abis == ['arm64-v8a', 'x86_64'], f"Unexpected ABIs: {abis}"
        for path in pinned:
            relative = path.relative_to(root).as_posix()
            if path.suffix == '.realmz2':
                assert archive.getinfo('assets/' + relative).compress_type == zipfile.ZIP_STORED, relative
            expected = hashlib.sha256(path.read_bytes()).hexdigest()
            actual = hashlib.sha256(archive.read('assets/' + relative)).hexdigest()
            assert actual == expected, f"Packaged content differs: {relative}"
            hashes[relative] = actual
    return {"apkSha256": hashlib.sha256(apk.read_bytes()).hexdigest(), "abis": abis,
            "signingCertificateSha256": certificate.group(1), "pinnedFiles": hashes,
            "permissions": permissions, "minSdk": 24, "targetSdk": 36, "crcValid": True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('build_directory', type=Path)
    args = parser.parse_args()
    directory = args.build_directory
    result = verify(directory / 'Realmz-Rebuilt-preview.apk', directory / 'manifest.txt', directory / 'signature.txt')
    (directory / 'apk-verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Android signature, manifest, CRC, ABIs and pinned content verified.')
