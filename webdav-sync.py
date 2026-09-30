#!/usr/bin/env python3
"""增量同步 iCloud 的 deb 归档到坚果云 WebDAV 镜像（多项目）。

用法（构建归档 iCloud 后执行）:
    python3 webdav-sync.py            # 默认 TypeX
    python3 webdav-sync.py PixPin     # 指定项目（Downloads 下的目录名）
    python3 webdav-sync.py TypeX PixPin KayokoX PullOver-X

行为约定（2026-09-29 起，每次构建归档后都要跑一次对应项目）:
- iCloud 源: ~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/<项目>/<子目录>/
- WebDAV 目标: https://dav.jianguoyun.com/dav/<项目>/<子目录>/，结构一一对应
- 只同步 *.deb（跳过隐藏文件），旧版本两侧都保留
- 远端缺失或文件大小不一致才 PUT；同步后对账，不一致退出码 1；重跑幂等
- 鉴权走 ~/.netrc 的 dav.jianguoyun.com 条目（curl --netrc），本脚本与仓库均不含密码
"""
import os
import re
import subprocess
import sys
import urllib.parse

BASE = "https://dav.jianguoyun.com/dav"
DOWNLOADS = os.path.expanduser(
    "~/Library/Mobile Documents/com~apple~CloudDocs/Downloads")


def curl(method, url, extra=()):
    return subprocess.run(
        ["curl", "-s", "-m", "300", "--netrc", "-X", method, url,
         "-o", "/dev/null", "-w", "%{http_code}", *extra],
        capture_output=True, text=True).stdout.strip()


def propfind_files(url):
    """Return {filename: size} for files in a collection, or None if absent."""
    code = curl("PROPFIND", url, ("-H", "Depth: 1"))
    if code == "404":
        return None
    if code != "207":
        raise RuntimeError(f"PROPFIND {url} -> HTTP {code}")
    xml = subprocess.run(
        ["curl", "-s", "-m", "300", "--netrc", "-X", "PROPFIND",
         "-H", "Depth: 1", url], capture_output=True, text=True).stdout
    collection = urllib.parse.urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    files = {}
    for block in re.split(r"<[dD]:response>", xml)[1:]:
        href = re.search(r"<[dD]:href>([^<]*)</[dD]:href>", block)
        size = re.search(r"<[dD]:getcontentlength>(\d+)</[dD]:getcontentlength>", block)
        if not href or not size:
            continue
        name = urllib.parse.unquote(href.group(1).rstrip("/").rsplit("/", 1)[-1])
        if name == collection:
            continue  # 坚果云会把目录自身也返回一条 size=0 记录
        files[name] = int(size.group(1))
    return files


def local_debs(local_dir):
    return sorted(f for f in os.listdir(local_dir)
                  if f.endswith(".deb") and not f.startswith("."))


def sync_project(project):
    local_root = os.path.join(DOWNLOADS, project)
    remote_root = f"{BASE}/{urllib.parse.quote(project)}"
    if not os.path.isdir(local_root):
        sys.exit(f"iCloud 归档目录不存在: {local_root}")
    print(f"\n===== {project}: {local_root} -> {remote_root} =====")
    subs = sorted(d for d in os.listdir(local_root)
                  if os.path.isdir(os.path.join(local_root, d)) and not d.startswith("."))
    print(f"本地归档子目录: {subs}")
    root_code = curl("MKCOL", remote_root)
    assert root_code in ("201", "405"), f"MKCOL {project} -> HTTP {root_code}"
    uploaded = skipped = 0
    for sub in subs:
        code = curl("MKCOL", f"{remote_root}/{sub}")
        assert code in ("201", "405"), f"MKCOL {project}/{sub} -> HTTP {code}"
        files = local_debs(os.path.join(local_root, sub))
        remote = propfind_files(f"{remote_root}/{sub}") or {}
        print(f"\n[{sub}] 本地 {len(files)} 个 deb，远端已有 {len(remote)} 个")
        for name in files:
            size = os.path.getsize(os.path.join(local_root, sub, name))
            if remote.get(name) == size:
                skipped += 1
                continue
            reason = "远端缺失" if name not in remote else f"大小不一致(远端 {remote.get(name)})"
            code = curl("PUT", f"{remote_root}/{sub}/{urllib.parse.quote(name)}",
                        ("--data-binary", "@" + os.path.join(local_root, sub, name)))
            if code not in ("200", "201", "204"):
                sys.exit(f"上传失败: {project}/{sub}/{name} HTTP {code}")
            uploaded += 1
            print(f"  上传: {name} ({size} B, {reason})")
    print(f"同步完成：上传 {uploaded}，一致跳过 {skipped}")

    mismatch = []
    for sub in subs:
        remote = propfind_files(f"{remote_root}/{sub}") or {}
        for name in local_debs(os.path.join(local_root, sub)):
            size = os.path.getsize(os.path.join(local_root, sub, name))
            if remote.get(name) != size:
                mismatch.append(f"  {project}/{sub}/{name}: 本地 {size} 远端 {remote.get(name)}")
    print("对账: " + ("全部一致 ✅" if not mismatch else "不一致 ❌\n" + "\n".join(mismatch)))
    return not mismatch


def main():
    projects = sys.argv[1:] or ["TypeX"]
    ok = all(sync_project(project) for project in projects)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
