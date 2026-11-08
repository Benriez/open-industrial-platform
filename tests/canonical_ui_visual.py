#!/usr/bin/env python3
"""Hash-derived, data-tolerant visual regression for the canonical left shell.

The stable left shell is compared pixel-by-pixel. Dynamic work content and the
historical footer are excluded by the manifest crop. Browser semantics and
geometry are separate mandatory gates. This is technical evidence, never an
operator visual approval.
"""
import argparse
import hashlib
import io
import json
import re
import tarfile
import tempfile
from pathlib import Path

import PIL
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[1]
MEAN_ABSOLUTE_DIFFERENCE_LIMIT = 0.01
CHANGED_PIXEL_RATIO_LIMIT = 0.01
CHANNEL_CHANGE_THRESHOLD = 32


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


_DERIVATION_CACHE = {}


def derive_reference(reference: dict) -> dict:
    """Re-create the pinned crop and compare pixels, not encoder output."""
    key = (reference['archive'], reference['archiveMember'], tuple(reference['crop']))
    if key in _DERIVATION_CACHE:
        return _DERIVATION_CACHE[key]
    archive_path = Path(reference['archive'])
    if not archive_path.is_file():
        result = {
            'ok': True,
            'available': False,
            'status': 'SKIPPED_EXTERNAL_ARCHIVE_UNAVAILABLE',
            'reason': 'The committed baseline and its pinned SHA-256 remain authoritative.',
        }
        _DERIVATION_CACHE[key] = result
        return result
    with tarfile.open(archive_path, 'r:gz') as archive:
        source = archive.extractfile(reference['archiveMember']).read()
    if hashlib.sha256(source).hexdigest() != reference['archiveMemberSha256']:
        result = {'ok': False, 'available': True, 'reason': 'upstream member hash drift'}
        _DERIVATION_CACHE[key] = result
        return result
    crop = reference['crop']
    with Image.open(io.BytesIO(source)) as image:
        derived = image.convert('RGB').crop(tuple(crop))
    with Image.open(ROOT / reference['path']) as committed:
        committed_pixels = committed.convert('RGB')
        identical = derived.size == committed_pixels.size and \
            ImageChops.difference(derived, committed_pixels).getbbox() is None
    result = {
        'ok': identical,
        'available': True,
        'status': 'DERIVED_AND_PIXEL_VERIFIED' if identical else 'PIXEL_MISMATCH',
        'archive': str(archive_path),
        'archive_member': reference['archiveMember'],
        'pixel_comparison': 'IDENTICAL' if identical else 'DIFFERENT',
        'expected_baseline_sha256': reference['sha256'],
        'pillow_version': PIL.__version__,
    }
    _DERIVATION_CACHE[key] = result
    return result


def compare(reference: dict, actual_root: Path) -> dict:
    width, height = reference['width'], reference['height']
    crop = reference['crop']
    baseline_path = ROOT / reference['path']
    actual_path = actual_root / f'canonical-ui-{width}.png'
    derivation = derive_reference(reference)
    result = {
        'width': width,
        'height': height,
        'baseline': str(baseline_path),
        'baseline_sha256': sha256(baseline_path),
        'expected_baseline_sha256': reference['sha256'],
        'actual': str(actual_path),
        'actual_sha256': sha256(actual_path),
        'crop': crop,
        'archive_derivation': derivation,
        'dynamic_data_policy': 'Only the manifest-cropped stable left shell is compared; workspace values and the historical footer are excluded. Semantic shell/workstation and geometry checks are separate mandatory gates.',
        'operator_visual_approval': 'VISUAL_PENDING_OPERATOR_ACCEPTANCE',
    }
    if not derivation['ok']:
        result.update(ok=False, reason='reference crop derivation failed')
        return result
    if result['baseline_sha256'] != reference['sha256']:
        result['ok'] = False
        result['reason'] = 'baseline hash drift'
        return result
    with Image.open(baseline_path) as baseline_image, Image.open(actual_path) as actual_image:
        if actual_image.size != (width, height):
            result['ok'] = False
            result['reason'] = f'actual dimensions {actual_image.size}, expected {(width, height)}'
            return result
        baseline = baseline_image.convert('RGB')
        actual = actual_image.convert('RGB').crop(tuple(crop))
        if baseline.size != actual.size:
            result['ok'] = False
            result['reason'] = f'baseline crop {baseline.size}, actual crop {actual.size}'
            return result
        difference = ImageChops.difference(baseline, actual)
        mean = sum(ImageStat.Stat(difference).mean) / (3 * 255)
        changed = sum(1 for pixel in difference.getdata() if max(pixel) > CHANNEL_CHANGE_THRESHOLD)
        ratio = changed / (baseline.width * baseline.height)
        blurred = ImageChops.difference(
            baseline.filter(ImageFilter.GaussianBlur(0.6)),
            actual.filter(ImageFilter.GaussianBlur(0.6)))
        blurred_mean = sum(ImageStat.Stat(blurred).mean) / (3 * 255)
        result.update({
            'mean_absolute_difference': mean,
            'mean_absolute_difference_limit': MEAN_ABSOLUTE_DIFFERENCE_LIMIT,
            'antialias_tolerant_mean_absolute_difference': blurred_mean,
            'antialias_tolerant_limit': 0.02,
            'changed_pixel_ratio': ratio,
            'changed_pixel_ratio_limit': CHANGED_PIXEL_RATIO_LIMIT,
            'channel_change_threshold': CHANNEL_CHANGE_THRESHOLD,
        })
        result['ok'] = mean <= MEAN_ABSOLUTE_DIFFERENCE_LIMIT and \
            blurred_mean <= 0.02 and ratio <= CHANGED_PIXEL_RATIO_LIMIT
        if not result['ok']:
            result['reason'] = 'stable shell pixels differ beyond the technical tolerances'
        return result


def negative_control(reference: dict, size: str) -> dict:
    """Prove detection of a large band and of a single navigation-row mutation."""
    width, height = reference['width'], reference['height']
    with tempfile.TemporaryDirectory(prefix='oip-ui-negative-control-') as directory:
        mutated = Image.new('RGB', (width, height), (10, 12, 18))
        with Image.open(ROOT / reference['path']) as shell:
            mutated.paste(shell.convert('RGB'), (0, 0))
        draw = ImageDraw.Draw(mutated)
        top, bottom = (120, 148) if size == 'single-navigation-row' else (260, 520)
        for y in range(top, bottom):
            ratio = (y - top) / max(1, bottom - top)
            draw.line((0, y, reference['crop'][2], y),
                      fill=(int(70 + 160 * ratio), 40, int(170 + 70 * (1 - ratio))))
        mutated.save(Path(directory) / f'canonical-ui-{width}.png')
        comparison = compare(reference, Path(directory))
        margins = [
            comparison.get('mean_absolute_difference', 0) / MEAN_ABSOLUTE_DIFFERENCE_LIMIT,
            comparison.get('antialias_tolerant_mean_absolute_difference', 0) / 0.02,
            comparison.get('changed_pixel_ratio', 0) / CHANGED_PIXEL_RATIO_LIMIT,
        ]
        margin = max(margins)
        return {
            'width': width,
            'mutation': size,
            'detected': not comparison['ok'] and margin >= 2.0,
            'detection_margin': margin,
            'required_detection_margin': 2.0,
            'mean_absolute_difference': comparison.get('mean_absolute_difference'),
            'antialias_tolerant_mean_absolute_difference': comparison.get('antialias_tolerant_mean_absolute_difference'),
            'changed_pixel_ratio': comparison.get('changed_pixel_ratio'),
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--actual-root', required=True)
    parser.add_argument('--manifest', default=str(ROOT / 'docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json'))
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    actual_root = Path(args.actual_root)
    manifest = json.loads(Path(args.manifest).read_text())
    shell_source = (ROOT / 'apps/flutter/lib/app/app.dart').read_text()
    crop_invariant_ok = all(
        reference['crop'][2] == 224 and
        re.search(r'SizedBox\(width:\s*224,\s*child:\s*_sidebar', shell_source)
        for reference in manifest['technicalVisualReferences'])
    crop_invariant = {
        'ok': crop_invariant_ok,
        'expected_shell_width': 224,
        'evidence': 'manifest crop and tolerant source geometry check; rendered workstation/selector semantics are separately asserted by the browser gate',
    }
    comparisons = [compare(reference, actual_root) for reference in manifest['technicalVisualReferences']]
    negative_controls = [negative_control(reference, size)
                         for reference in manifest['technicalVisualReferences']
                         for size in ['single-navigation-row', 'large-gradient-band']]
    negative_controls_pass = all(item['detected'] for item in negative_controls)
    receipt = {
        'schema': 'oip-canonical-ui-visual-comparison-v2',
        'verdict': 'PASS' if all(item['ok'] for item in comparisons) and negative_controls_pass and crop_invariant_ok else 'FAIL',
        'crop_invariant': crop_invariant,
        'comparisons': comparisons,
        'negative_controls': negative_controls,
        'negative_controls_pass': negative_controls_pass,
        'operator_visual_approval': 'VISUAL_PENDING_OPERATOR_ACCEPTANCE',
        'handoff_manifest': args.manifest,
    }
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'verdict': receipt['verdict'], 'comparisons': len(comparisons),
                      'negative_controls_pass': negative_controls_pass,
                      'failed': [item['width'] for item in comparisons if not item['ok']]}, indent=2))
    return 0 if receipt['verdict'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
