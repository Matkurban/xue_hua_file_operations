#!/usr/bin/env python3
"""Drives the Android system camera app for the flutter_driver capture tests.

flutter_driver cannot reach the camera app (another process), so run this
helper next to `flutter drive`:

    python3 test_driver/tools/android_camera_helper.py <adb> <serial> <applicationId>

It taps "Allow" on runtime permission dialogs (no `pm grant`: that would
kill the app under test) and keeps watching the screen. When the AOSP Camera2 app (com.android.camera2) shows up it taps
"Shutter" (photo: once; video: once to start, again after ~3 s to stop (~2 s of footage)) and
then the review "Done" button. Stops after 20 minutes or on Ctrl-C.

Notes on emulator Camera2 paths (AOSP OneCamCreator):
- LEGACY_JPEG (e.g. API24) → SimpleImageCaptureCommand → review Done quickly
- ZSL (e.g. API36) → ZslImageCaptureCommand → review Done
- LIMITED_YUV (e.g. API28/31 + VirtualScene back cam) → ConvergedImageCaptureCommand
  often never delivers a YUV still on emulator; AVD back camera must be Emulated
  (Google issuetracker 209835361). Locale Done label may be 「完成」.
- On API36, dumpsys window may report mCurrentFocus=null; helper also
  reads mFocusedApp so Camera2 / permission UI is still detected.
"""
import re, subprocess, sys, time
import xml.etree.ElementTree as ET

adb, serial, app_id = sys.argv[1:4]


def sh(*args, timeout=30):
    return subprocess.run([adb, '-s', serial, *args], capture_output=True,
                          text=True, timeout=timeout).stdout


def ui():
    sh('shell', 'uiautomator', 'dump', '/sdcard/ui_helper.xml')
    xml = sh('shell', 'cat', '/sdcard/ui_helper.xml')
    try:
        return ET.fromstring(xml)
    except ET.ParseError:
        return None


def find(root, rid=None, desc=None, text=None, enabled=None):
    for node in root.iter('node'):
        if rid and not node.get('resource-id', '').endswith(rid):
            continue
        if desc is not None:
            d = node.get('content-desc', '')
            if isinstance(desc, (list, tuple)):
                if d not in desc:
                    continue
            elif d != desc:
                continue
        if text and node.get('text', '') != text:
            continue
        if enabled is not None and (node.get('enabled') == 'true') != bool(enabled):
            continue
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            return (x1 + x2) // 2, (y1 + y2) // 2
    return None


def find_node(root, rid=None, desc=None):
    for node in root.iter('node'):
        if rid and not node.get('resource-id', '').endswith(rid):
            continue
        if desc is not None:
            d = node.get('content-desc', '')
            if isinstance(desc, (list, tuple)):
                if d not in desc:
                    continue
            elif d != desc:
                continue
        return node
    return None


def tap(point, what):
    print(f'[helper] tap {what} at {point}', flush=True)
    sh('shell', 'input', 'tap', str(point[0]), str(point[1]))


def find_done(root):
    # API36 zh-Hans uses content-desc 「完成」; en uses 「Done」.
    return (find(root, rid='done_button')
            or find(root, desc=['Done', '完成', 'Done!']))


deadline = time.time() + 20 * 60
shutter_taps = 0
shutter_at = 0.0
while time.time() < deadline:
    focus = sh('shell', 'dumpsys', 'window')
    # API36+ often leaves mCurrentFocus=null while mFocusedApp still names the
    # camera / permission UI; join both so we do not miss CaptureActivity.
    current = ''.join(
        l for l in focus.splitlines()
        if 'mCurrentFocus' in l or 'mFocusedApp' in l)
    if 'permissioncontroller' in current or 'packageinstaller' in current:
        root = ui()
        allow = root is not None and (
            find(root, rid='permission_allow_foreground_only_button')
            or find(root, rid='permission_allow_button')
            or find(root, rid='permission_allow_one_time_button'))
        if allow:
            tap(allow, 'permission Allow')
        time.sleep(1)
        continue
    if 'com.android.camera2' not in current:
        shutter_taps = 0
        shutter_at = 0.0
        time.sleep(1)
        continue
    root = ui()
    if root is None:
        time.sleep(1)
        continue
    done = find_done(root)
    if done:
        tap(done, 'Done')
        shutter_taps = 0
        shutter_at = 0.0
        time.sleep(2)
        continue
    shutter = find(root, rid='shutter_button', enabled=True)
    if shutter and shutter_taps == 0:
        # Wait until Camera2 reports ReadyForCapture is visible as enabled shutter.
        # Preview warm-up: LEGACY/ZSL need ~2s; LIMITED needs AE settle before Converged.
        time.sleep(2.0)
        # Re-check still enabled after settle
        root2 = ui()
        if root2 is None:
            time.sleep(1)
            continue
        if find_done(root2):
            continue
        shutter = find(root2, rid='shutter_button', enabled=True)
        if not shutter:
            time.sleep(1)
            continue
        # Tap preview center once so AFScan runs before still capture (helps Converged path).
        tap((shutter[0], max(200, shutter[1] // 2)), 'preview AF')
        time.sleep(1.5)
        tap(shutter, 'Shutter')
        shutter_taps = 1
        shutter_at = time.time()
        if 'VideoCamera' in current:  # VIDEO_CAPTURE intent
            # Longer start-up before stop: Camera2 on some API levels NPEs in
            # saveVideo if stop is pressed before the recorder is ready.
            time.sleep(5)
            tap(shutter, 'Shutter (stop)')
            shutter_at = time.time()
        time.sleep(1)
        continue
    # After shutter: keep polling for Done; if shutter re-enables without Done,
    # retry once (ConvergedImageCapture can fail once then recover on Emulated).
    if shutter_taps == 1 and shutter and (time.time() - shutter_at) > 8:
        print('[helper] shutter re-enabled without Done; retrying shutter once', flush=True)
        tap((shutter[0], max(200, shutter[1] // 2)), 'preview AF')
        time.sleep(1.5)
        tap(shutter, 'Shutter (retry)')
        shutter_taps = 2
        shutter_at = time.time()
        time.sleep(1)
        continue
    time.sleep(1)
