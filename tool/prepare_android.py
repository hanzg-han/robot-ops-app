#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""生成并加固 Android 平台工程（CI 专用）。

背景：本工程的 `android/` 目录不入库（见 .gitignore），由 CI 用
`flutter create --platforms=android .` 生成后再执行本脚本做必要加固。

本脚本做四件事：
1. 在 AndroidManifest.xml 的 <application> 上补 `android:usesCleartextTraffic="true"`
   —— 底盘接口仅有明文 HTTP，无 HTTPS（开发文档 §8.3 / PRD §8.3），
   不加此配置请求会被系统拦截（开发文档 §17 坑 11）。
2. 补 <uses-permission android:name="android.permission.INTERNET" />（仅需网络权限）。
3. 设置中文 App 名称，并统一 applicationId / namespace。
4. 注入发布签名配置：当 android/key.properties 存在时（CI 从 Secrets 还原），
   debug 与 release 都使用同一把固定密钥签名。

为什么必须固定签名（关键经验，勿删）：
   AGP 默认的 debug 签名用的是 `~/.android/debug.keystore`。CI 每次运行都是全新
   HOME，AGP 会现场新建该文件，于是**每一轮 CI 产出的 APK 签名证书都不同**。
   后果是后一轮的 APK 无法覆盖安装前一轮的 APK，安装器会直接报解析/包信息错误。
   把密钥固定下来后，debug 与 release 还能互相覆盖安装。

所有加固项在写盘后都会回读校验：只要有一项没真正生效，脚本以非 0 退出，
避免"脚本报成功、但产物其实没改"的静默失败（曾发生过：Flutter 3.24.5 模板写的是
`namespace = "..."`（带等号），而旧正则只匹配不带等号的写法，导致包名加固静默失效）。

脚本是幂等的：重复执行不会产生重复节点。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# 与 README 中 `flutter create --org com.wizrole --project-name robot_ops_app` 推导一致。
# 注意：改这里等于改 App 身份，已安装的设备必须先卸载旧包，否则覆盖安装会被系统拒绝。
APPLICATION_ID = "com.wizrole.robot_ops_app"
APP_LABEL = "导诊机器人运维"

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
BUILD_GRADLE = Path("android/app/build.gradle")
BUILD_GRADLE_KTS = Path("android/app/build.gradle.kts")
KEY_PROPERTIES = Path("android/key.properties")

# 兼容 `key = "value"`（Flutter 3.24.5 模板）与 `key "value"`（早期模板）两种写法。
_NS_RE = re.compile(r'namespace\s*=?\s*"[^"]*"')
_ID_RE = re.compile(r'applicationId\s*=?\s*"[^"]*"')
_DEBUG_SIGNING_RE = re.compile(r"signingConfig\s*=?\s*signingConfigs\.debug")

# Groovy 版：读取 key.properties（放在 android/ 下，被 .gitignore 忽略）
_GROOVY_PROPERTIES_BLOCK = """// 发布签名配置：CI 从 Secrets 还原密钥库后生成 android/key.properties。
// 本机没有 key.properties 时自动回落到 AGP 默认签名，不影响 `flutter run`。
def keystoreProperties = new java.util.Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.withInputStream { keystoreProperties.load(it) }
}

"""

_GROOVY_SIGNING_BLOCK = """    signingConfigs {
        // debug 与 release 共用同一把固定密钥：CI 每轮重建 ~/.android/debug.keystore
        // 会让不同轮次的 APK 签名不一致，导致无法覆盖安装。
        // 仅在 key.properties 存在（CI 从 Secrets 还原了密钥）时才声明 debug 覆盖，
        // 否则会把本机开发用的 AGP 默认 debug 签名配置改成空配置而构建失败。
        if (keystoreProperties["storeFile"]) {
            debug {
                storeFile = file(keystoreProperties["storeFile"])
                storePassword = keystoreProperties["storePassword"]
                keyAlias = keystoreProperties["keyAlias"]
                keyPassword = keystoreProperties["keyPassword"]
            }
        }
        release {
            if (keystoreProperties["storeFile"]) {
                storeFile = file(keystoreProperties["storeFile"])
                storePassword = keystoreProperties["storePassword"]
                keyAlias = keystoreProperties["keyAlias"]
                keyPassword = keystoreProperties["keyPassword"]
            }
        }
    }

"""


def fail(msg: str) -> None:
    print(f"[prepare_android] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg: str) -> None:
    print(f"[prepare_android] {msg}")


def _app_tag_end(text: str) -> int:
    """返回 <application …> 起始标签的 '>' 下标（-1 表示未找到）。"""
    idx = text.find("<application")
    if idx < 0:
        return -1
    return text.find(">", idx)


def _insert_app_attr(text: str, attr: str) -> str:
    """把属性插入到 <application …> 起始标签内（保持合法 XML）。

    刻意不使用 re.sub 的反向引用：非 raw 替换串会把 `\\1` 变成字面反斜杠，
    从而生成非法 XML（CI 上曾报 "Please ensure that the android manifest
    is a valid XML document"）。
    """
    end = _app_tag_end(text)
    if end < 0:
        fail("AndroidManifest.xml 缺少 <application> 标签")
    return text[:end] + "\n        " + attr + text[end:]


def ensure_manifest() -> None:
    if not MANIFEST.exists():
        fail(f"未找到 {MANIFEST}；请先执行 flutter create --platforms=android .")

    text = MANIFEST.read_text(encoding="utf-8")
    original = text

    # 1) 明文流量例外（局域网明文 HTTP 必需，开发文档 §8.3 / §17 坑 11）
    if "usesCleartextTraffic" not in text:
        text = _insert_app_attr(text, 'android:usesCleartextTraffic="true"')
        info('已加入 android:usesCleartextTraffic="true"（局域网明文 HTTP 必需）')
    else:
        info("usesCleartextTraffic 已存在，跳过")

    # 2) INTERNET 权限（仅需网络权限，PRD §8.3）
    if "android.permission.INTERNET" not in text:
        idx = text.find("<manifest")
        if idx < 0:
            fail("AndroidManifest.xml 缺少 <manifest> 根标签")
        end = text.find(">", idx)
        if end < 0:
            fail("AndroidManifest.xml 的 <manifest> 标签未闭合")
        insert = (
            "\n    <!-- 仅需网络权限（PRD §8.3） -->"
            '\n    <uses-permission android:name="android.permission.INTERNET"/>'
        )
        text = text[: end + 1] + insert + text[end + 1 :]
        info("已加入 INTERNET 权限")
    else:
        info("INTERNET 权限已存在，跳过")

    # 3) App 中文名称
    if 'android:label="' in text:
        text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', text)
    else:
        text = _insert_app_attr(text, f'android:label="{APP_LABEL}"')
    info(f"已设置 App 名称：{APP_LABEL}")

    if text != original:
        MANIFEST.write_text(text, encoding="utf-8")
        info(f"已写入 {MANIFEST}")
    else:
        info("Manifest 无需变更")

    # 写后校验：三项加固必须真的落到文件里。
    final = MANIFEST.read_text(encoding="utf-8")
    for needle in (
        'android:usesCleartextTraffic="true"',
        "android.permission.INTERNET",
        f'android:label="{APP_LABEL}"',
    ):
        if needle not in final:
            fail(f"Manifest 加固校验失败：缺少 {needle}")
    info("Manifest 加固校验通过")


def _apply_identifier(path: Path) -> None:
    """把 namespace / applicationId 统一为 APPLICATION_ID，并回读校验。

    统一写成 `key = "value"`：Groovy 与 Kotlin DSL 都接受这种赋值写法。
    """
    text = path.read_text(encoding="utf-8")
    original = text

    text, ns_hits = _NS_RE.subn(f'namespace = "{APPLICATION_ID}"', text)
    text, id_hits = _ID_RE.subn(f'applicationId = "{APPLICATION_ID}"', text)

    if ns_hits == 0 or id_hits == 0:
        fail(
            f"{path} 未匹配到 namespace/applicationId"
            f"（namespace 命中 {ns_hits} 处、applicationId 命中 {id_hits} 处）；"
            "Flutter 模板结构可能已变化，需人工检查"
        )

    if text != original:
        path.write_text(text, encoding="utf-8")
        info(f"已写入 {path}")
    else:
        info(f"{path} 无需变更")

    final = path.read_text(encoding="utf-8")
    for expected in (
        f'namespace = "{APPLICATION_ID}"',
        f'applicationId = "{APPLICATION_ID}"',
    ):
        if expected not in final:
            fail(f"{path} 的包名加固未生效（期望包含 {expected}）")
    info(f"已确认 applicationId / namespace = {APPLICATION_ID}")


def ensure_signing(path: Path) -> None:
    """向 Groovy build.gradle 注入固定签名配置（幂等）。"""
    text = path.read_text(encoding="utf-8")

    if "keystoreProperties" in text:
        info("签名配置已存在，跳过注入")
        return

    android_idx = text.find("\nandroid {")
    if android_idx < 0:
        fail(f"{path} 未找到 `android {{` 块，无法注入签名配置")

    # 1) 属性读取块插到 android 块之前
    text = text[:android_idx] + "\n" + _GROOVY_PROPERTIES_BLOCK.rstrip("\n") + text[android_idx :]

    # 2) signingConfigs 块插到 android 块之后
    android_idx = text.find("\nandroid {")
    brace_end = text.find("\n", android_idx + 1)
    text = text[: brace_end + 1] + _GROOVY_SIGNING_BLOCK + text[brace_end + 1 :]

    # 3) release 改用固定密钥（无 key.properties 时回落 debug）
    text, hits = _DEBUG_SIGNING_RE.subn(
        'signingConfig = keystoreProperties["storeFile"]'
        " ? signingConfigs.release : signingConfigs.debug",
        text,
    )
    if hits == 0:
        fail(f"{path} 未找到 `signingConfig = signingConfigs.debug`，无法切换到发布签名")

    path.write_text(text, encoding="utf-8")
    info(f"已注入固定签名配置：{path}")

    final = path.read_text(encoding="utf-8")
    for expected in (
        "keystoreProperties",
        "signingConfigs {",
        "signingConfigs.release",
        'signingConfig = keystoreProperties["storeFile"]',
    ):
        if expected not in final:
            fail(f"签名配置校验失败：{path} 缺少 {expected}")

    if KEY_PROPERTIES.exists():
        info(f"检测到 {KEY_PROPERTIES} → debug/release 均使用固定密钥签名")
    else:
        info(f"未检测到 {KEY_PROPERTIES} → 回落 AGP 默认签名（本机开发场景）")
    info("签名配置校验通过")


def ensure_identifier_and_signing() -> None:
    """统一包名，并注入固定签名配置。"""
    if BUILD_GRADLE.exists():
        _apply_identifier(BUILD_GRADLE)
        ensure_signing(BUILD_GRADLE)
    elif BUILD_GRADLE_KTS.exists():
        _apply_identifier(BUILD_GRADLE_KTS)
        fail(
            "检测到 Kotlin DSL（build.gradle.kts），本脚本的签名注入仅支持 Groovy。"
            "若 Flutter 模板已切换到 .kts，请同步更新本脚本的 ensure_signing()。"
        )
    else:
        fail("未找到 android/app/build.gradle(.kts)")


def main() -> None:
    if not Path("android").exists():
        fail("android/ 目录不存在；请先执行 flutter create --platforms=android .")
    ensure_manifest()
    ensure_identifier_and_signing()
    info("Android 平台工程加固完成")


if __name__ == "__main__":
    main()
