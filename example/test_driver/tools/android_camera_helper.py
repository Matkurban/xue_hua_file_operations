#!/usr/bin/env python3
"""Drives the Android system camera app for the flutter_driver capture tests.

flutter_driver cannot reach the camera app (another process), so run this
helper next to `flutter drive`:

    python3 test_driver/tools/android_camera_helper.py <adb> <serial> <applicationId>

It grants the CAMERA / RECORD_AUDIO permissions, then keeps watching the
screen. When the AOSP Camera2 app (com.android.camera2) shows up it taps
"Shutter" (photo: once; video: once to start, again after ~3 s to stop) and
then the review "Done" button. Stops after 20 minutes or on Ctrl-C.
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


def find(root, rid=None, desc=None, text=None):
    for node in root.iter('node'):
        if rid and not node.get('resource-id', '').endswith(rid):
            continue
        if desc and node.get('content-desc', '') != desc:
            continue
        if text and node.get('text', '') != text:
            continue
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            return (x1 + x2) // 2, (y1 + y2) // 2
    return None


def tap(point, what):
    print(f'[helper] tap {what} at {point}', flush=True)
    sh('shell', 'input', 'tap', str(point[0]), str(point[1]))


def action():
    out = sh('shell', 'dumpsys', 'activity', 'activities')
    m = re.search(r'act=android\.media\.action\.(\w+)', out)
    return m.group(1) if m else ''


deadline = time.time() + 20 * 60
last_perm = 0
shutter_taps = 0
while time.time() < deadline:
    if time.time() - last_perm > 2:
        for perm in ('CAMERA', 'RECORD_AUDIO'):
            sh('shell', 'pm', 'grant', app_id, f'android.permission.{perm}')
        last_perm = time.time()
    focus = sh('shell', 'dumpsys', 'window')
    if 'com.android.camera2' not in ''.join(
            l for l in focus.splitlines() if 'mCurrentFocus' in l):
        shutter_taps = 0
        time.sleep(1)
        continue
    root = ui()
    if root is None:
        time.sleep(1)
        continue
    done = find(root, rid='done_button') or find(root, desc='Done')
    if done:
        tap(done, 'Done')
        shutter_taps = 0
        time.sleep(2)
        continue
    shutter = find(root, rid='shutter_button')
    if shutter and shutter_taps == 0:
        time.sleep(1.5)  # let the preview warm up
        tap(shutter, 'Shutter')
        shutter_taps = 1
        if 'VIDEO' in action():
            time.sleep(3)
            tap(shutter, 'Shutter (stop)')
        time.sleep(2)
        continue
    time.sleep(1)
