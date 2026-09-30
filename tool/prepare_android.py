#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""生成并加固 Android 平台工程（CI 专用）。

背景：本工程的 `android/` 目录不入库（见 .gitignore），由 CI 用
`flutter create --platforms=android .` 生成后再执行本脚本做必要加固。

本脚本做三件事：
1. 在 AndroidManifest.xml 的 <application> 上补 `android:usesCleartextTraffic="true"`
   —— 底盘接口仅有明文 HTTP，无 HTTPS（开发文档 §8.3 / PRD §8.3），
   不加此配置请求会被系统拦截（开发文档 §17 坑 11）。
2. 补 <uses-permission android:name="android.permission.INTERNET" />（仅需网络权限）。
3. 把 applicationId / namespace 统一为 com.wizrole.robotops，并设置中文 App 名称。

脚本是幂等的：重复执行不会产生重复节点。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

APPLICATION_ID = "com.wizrole.robotops"
APP_LABEL = "导诊机器人运维"

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
DEBUG_MANIFEST = Path("android/app/src/debug/AndroidManifest.xml")
BUILD_GRADLE = Path("android/app/build.gradle")
BUILD_GRADLE_KTS = Path("android/app/build.gradle.kts")


def fail(msg: str) -> None:
    print(f"[prepare_android] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg: str) -> None:
    print(f"[prepare_android] {msg}")


def ensure_manifest() -> None:
    if not MANIFEST.exists():
        fail(f"未找到 {MANIFEST}；请先执行 flutter create --platforms=android .")

    text = MANIFEST.read_text(encoding="utf-8")
    original = text

    # 1) 明文流量例外
    if "usesCleartextTraffic" not in text:
        text = re.sub(
            r"<application(\s)",
            '<application\n        android:usesCleartextTraffic="true"\\1',
            text,
            count=1,
        )
        info("已加入 android:usesCleartextTraffic=\"true\"（局域网明文 HTTP 必需）")
    else:
        info("usesCleartextTraffic 已存在，跳过")

    # 2) INTERNET 权限
    if "android.permission.INTERNET" not in text:
        text = re.sub(
            r"(<manifest[^>]*>)",
            r"\1\n    <!-- 仅需网络权限（PRD §8.3） -->\n"
            r"    <uses-permission android:name=\"android.permission.INTERNET\"/>",
            text,
            count=1,
        )
        info("已加入 INTERNET 权限")
    else:
        info("INTERNET 权限已存在，跳过")

    # 3) App 中文名称
    if 'android:label="' in text:
        text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', text)
    else:
        text = re.sub(
            r"<application(\s)",
            f'<application\n        android:label="{APP_LABEL}"\\1',
            text,
            count=1,
        )
    info(f"已设置 App 名称：{APP_LABEL}")

    if text != original:
        MANIFEST.write_text(text, encoding="utf-8")
        info(f"已写入 {MANIFEST}")
    else:
        info("Manifest 无需变更")


def ensure_identifier() -> None:
    """统一 applicationId / namespace。"""
    if BUILD_GRADLE_KTS.exists():
        path = BUILD_GRADLE_KTS
        text = path.read_text(encoding="utf-8")
        text = re.sub(r'namespace\s*=\s*"[^"]*"', f'namespace = "{APPLICATION_ID}"', text)
        text = re.sub(
            r'applicationId\s*=\s*"[^"]*"',
            f'applicationId = "{APPLICATION_ID}"',
            text,
        )
    elif BUILD_GRADLE.exists():
        path = BUILD_GRADLE
        text = path.read_text(encoding="utf-8")
        text = re.sub(r'namespace\s+"[^"]*"', f'namespace "{APPLICATION_ID}"', text)
        text = re.sub(
            r'applicationId\s+"[^"]*"',
            f'applicationId "{APPLICATION_ID}"',
            text,
        )
    else:
        fail("未找到 android/app/build.gradle(.kts)")
        return

    path.write_text(text, encoding="utf-8")
    info(f"已设置 applicationId / namespace = {APPLICATION_ID}")


def main() -> None:
    if not Path("android").exists():
        fail("android/ 目录不存在；请先执行 flutter create --platforms=android .")
    ensure_manifest()
    ensure_identifier()
    info("Android 平台工程加固完成")


if __name__ == "__main__":
    main()
