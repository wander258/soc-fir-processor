#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VCD 波形 -> 终端 ASCII 时序图

为什么需要这个：GTKWave 界面信息量太大，第一次看容易懵。
这个脚本把 VCD 里的波形直接画成 ASCII 图打印到终端，
一眼就能看出"哪个信号在第几纳秒变成了什么"。

用法（在 fir_soc 目录下）:
    python vcd_wave.py 01_counter\\tb_counter.vcd
    python vcd_wave.py 05_fir81\\tb_fir.vcd --sig clk,rst_n,en,din,dout,dout_v
    python vcd_wave.py 01_counter\\tb_counter.vcd --list
    python vcd_wave.py 01_counter\\tb_counter.vcd --radix dec --cols 30

图形说明:
    低电平 = _        高电平 = -        未知 = x        高阻 = z
    多比特信号按十六进制显示（想看成十进制加 --radix dec）
"""

import argparse
import os
import sys
from bisect import bisect_right

# 防止终端编码不支持某些字符时直接崩掉
try:
    sys.stdout.reconfigure(errors="replace")
except Exception:
    pass


# ----------------------------------------------------------------------
# 1. 解析 VCD
# ----------------------------------------------------------------------
def parse_vcd(path):
    """
    返回 (timescale, entries, order, max_time)

    注意一个 VCD 的坑：同一个标识符（比如 #）会在不同层次里重复声明，
    表示"其实是同一根线"。所以 entries[sid] 里存的是一个声明列表，
    数值变化则是这些声明共享的。
    """
    timescale = None
    scopes = []
    entries = {}          # sid -> {"changes": [...], "decls": [...]}
    order = []            # 保持出现顺序
    cur_time = 0
    max_time = 0
    in_comment = False

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].strip()
        i += 1
        if not line:
            continue

        if in_comment:
            if line.startswith("$end"):
                in_comment = False
            continue

        # ---- 指令行 ----
        if line.startswith("$"):
            tok = line.split()
            kw = tok[0]

            if kw == "$comment":
                if "$end" not in line:
                    in_comment = True

            elif kw == "$timescale":
                # $timescale 的值可能在下一行，要往下找
                if len(tok) > 1 and tok[1] != "$end":
                    timescale = tok[1]
                else:
                    while i < n:
                        nxt = lines[i].strip()
                        i += 1
                        if nxt and not nxt.startswith("$"):
                            timescale = nxt
                            break
                        if nxt.startswith("$end"):
                            break

            elif kw == "$scope":
                scopes.append(tok[2])

            elif kw == "$upscope":
                if scopes:
                    scopes.pop()

            elif kw == "$var":
                # $var <类型> <位宽> <标识> <名字> [<位选>] $end
                typ   = tok[1]
                width = int(tok[2])
                sid   = tok[3]
                name  = tok[4]
                if sid not in entries:
                    entries[sid] = {"changes": [], "decls": []}
                    order.append(sid)
                entries[sid]["decls"].append({
                    "full":  ".".join(scopes + [name]),
                    "short": name,
                    "width": width,
                    "type":  typ,
                    "scope": ".".join(scopes),
                })

            # 其它指令（$dumpvars/$dumpall/$end/...）忽略本行，
            # 但它们后面跟着的数值行要照常处理，所以不能跳过整块
            continue

        # ---- 时间戳 ----
        if line[0] == "#":
            try:
                cur_time = int(line[1:])
            except ValueError:
                continue
            if cur_time > max_time:
                max_time = cur_time
            continue

        # ---- 数值变化 ----
        c = line[0]
        if c in "01xXzZ":
            sid = line[1:]
            if sid in entries:
                entries[sid]["changes"].append((cur_time, c.lower()))
        elif c in "bB":
            parts = line[1:].split()
            if len(parts) == 2 and parts[1] in entries:
                entries[parts[1]]["changes"].append((cur_time, parts[0].lower()))
        elif c in "rR":
            parts = line[1:].split()
            if len(parts) == 2 and parts[1] in entries:
                entries[parts[1]]["changes"].append((cur_time, parts[0]))

    return timescale, entries, order, max_time


def build_views(entries, order):
    """把 (标识 -> 声明列表) 展开成一个个可显示的信号视图。"""
    views = []
    for sid in order:
        e = entries[sid]
        for d in e["decls"]:
            v = dict(d)
            v["changes"] = e["changes"]      # 共享同一份变化序列
            views.append(v)
    return views


# ----------------------------------------------------------------------
# 2. 取值 / 格式化
# ----------------------------------------------------------------------
def fmt_value(sig, raw, radix, signed=False):
    """
    把 VCD 里的原始值字符串格式化成好读的形式。

    signed=True 时按二进制补码解释成有符号数。
    VCD 格式本身不带符号信息，所以只能由调用方指定；
    十进制显示默认按有符号处理，否则 -1000 会显示成 64536。
    """
    if raw is None:
        return "x"
    if sig["width"] == 1:
        return raw
    if any(ch in raw for ch in "xz"):
        return raw
    try:
        bits = raw.zfill(sig["width"])
        v = int(bits, 2)
    except ValueError:
        return raw
    if signed and v >= (1 << (sig["width"] - 1)):
        v -= (1 << sig["width"])
    if radix == "dec":
        return str(v)
    if radix == "bin":
        return raw
    digits = max(1, (sig["width"] + 3) // 4)
    return "%0*X" % (digits, v)


def sig_label(s):
    name = s["short"]
    if s["width"] > 1:
        name += "[%d:0]" % (s["width"] - 1)
    return name


# ----------------------------------------------------------------------
# 3. 画图
# ----------------------------------------------------------------------
def render(sigs, cols, radix, from_t=None, to_t=None, signed=False):
    # 所有信号的变化时刻并成列 —— 不会漏掉任何跳变
    tset = set()
    for s in sigs:
        for t, _ in s["changes"]:
            if from_t is not None and t < from_t:
                continue
            if to_t is not None and t > to_t:
                continue
            tset.add(t)
    if from_t is not None:
        tset.add(from_t)                 # 窗口起点也要占一列，才能看到起始状态
    times = sorted(tset) or [0]
    times = times[:cols]

    # 列宽：先看多比特数值要多宽
    w = 2
    for s in sigs:
        if s["width"] > 1:
            for _, raw in s["changes"]:
                w = max(w, len(fmt_value(s, raw, radix, signed)) + 1)

    # 时间标签太长就隔几列打一个，不要让标签挤成一团
    max_label = max(len("%g" % (t / 1000.0)) for t in times)
    stride = max(1, -(-max_label // w))          # 向上取整
    w = max(w, 2)

    # 列太多就砍到总宽 118 以内
    max_cols = max(4, 118 // w)
    if len(times) > max_cols:
        times = times[:max_cols]

    lookups = []
    for s in sigs:
        lookups.append(([t for t, _ in s["changes"]], [v for _, v in s["changes"]], s))

    name_width = max(len(sig_label(s)) for s in sigs)
    pad = " " * (name_width + 2)

    out = []

    # 时间刻度线
    out.append(pad + "".join("|" + " " * (w - 1) for _ in times))

    # 时间标签
    label = [" "] * (name_width + 2 + w * len(times))
    for idx, t in enumerate(times):
        if idx % stride:
            continue
        txt = "%g" % (t / 1000.0)
        pos = (name_width + 2) + idx * w
        for j, ch in enumerate(txt):
            if pos + j < len(label):
                label[pos + j] = ch
    out.append("".join(label).rstrip())

    # 每个信号一行
    BITCHAR = {"0": "_", "1": "-", "x": "x", "z": "z"}
    for tl, vl, s in lookups:
        cells = []
        for t in times:
            k = bisect_right(tl, t) - 1
            raw = vl[k] if k >= 0 else None
            if s["width"] == 1:
                ch = fmt_value(s, raw, radix, signed)
                cells.append(BITCHAR.get(ch, "x") * w)
            else:
                cells.append(fmt_value(s, raw, radix, signed).rjust(w))
        out.append(sig_label(s).rjust(name_width) + "  " + "".join(cells).rstrip())

    return out, times


# ----------------------------------------------------------------------
# 4. main
# ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="把 VCD 波形画成终端 ASCII 时序图")
    ap.add_argument("vcd", help="VCD 文件路径")
    ap.add_argument("--sig", default=None,
                    help="只显示这些信号，逗号分隔（默认显示顶层 testbench 的信号）")
    ap.add_argument("--scope", default=None, help="只显示这个层次（如 tb_fir.dut）里的信号")
    ap.add_argument("--list", action="store_true", help="只列出所有信号名，不画图")
    ap.add_argument("--cols", type=int, default=48, help="最多画多少个时间片，默认 48")
    ap.add_argument("--from", dest="t_from", type=float, default=None,
                    help="从第几纳秒开始看（例如 --from 150）")
    ap.add_argument("--to", dest="t_to", type=float, default=None,
                    help="看到第几纳秒为止（例如 --to 250）")
    ap.add_argument("--radix", choices=["hex", "dec", "bin"], default="hex",
                    help="多比特信号的显示进制，默认 hex")
    ap.add_argument("--all", action="store_true",
                    help="包含 parameter/integer 等非 wire/reg 信号")
    ap.add_argument("--unsigned", action="store_true",
                    help="十进制显示时按无符号解释（默认按有符号补码，"
                         "这样 -1000 才不会显示成 64536）")
    args = ap.parse_args()

    if not os.path.exists(args.vcd):
        print("找不到文件: %s" % args.vcd)
        sys.exit(1)

    timescale, entries, order, max_time = parse_vcd(args.vcd)
    views = build_views(entries, order)
    if not views:
        print("这个 VCD 里没有解析到任何信号。")
        sys.exit(1)

    # ---- 选信号 ----
    if args.sig:
        want = [x.strip() for x in args.sig.split(",") if x.strip()]
        chosen = []
        for nm in want:
            # 同名信号可能在多个层次里出现（VCD 会复用同一个标识符），
            # 取最外层那个；想看内部信号就写全名，比如 dut.x[0]
            cands = [v for v in views if v["short"] == nm or v["full"] == nm]
            if cands:
                cands.sort(key=lambda v: (len(v["scope"].split(".")), v["full"]))
                chosen.append(cands[0])
        if not chosen:
            print("--sig 里写的名字一个都没匹配上。先用 --list 看看有哪些信号。")
            sys.exit(1)
    elif args.scope:
        chosen = [v for v in views if v["scope"] == args.scope or
                  v["scope"].endswith("." + args.scope)]
        if not chosen:
            print("--scope 没匹配上，先用 --list 看看层次名。")
            sys.exit(1)
    else:
        # 默认：最外层作用域，且类型是 wire/reg
        top = min(len(v["scope"].split(".")) for v in views)
        chosen = [v for v in views
                  if len(v["scope"].split(".")) == top
                  and (args.all or v["type"] in ("wire", "reg"))]
        if not chosen:                     # 兜底：顶层都是 parameter 之类
            chosen = [v for v in views if len(v["scope"].split(".")) == top]

    if args.list:
        print("=" * 78)
        print("文件: %s     时间单位: %s" % (args.vcd, timescale or "?"))
        print("=" * 78)
        for v in views:
            print("  %-38s 位宽=%-3d 类型=%s" % (v["full"], v["width"], v["type"]))
        print()
        print("提示: 用 --sig 名字1,名字2 只看你关心的信号")
        print("      dut 内部的信号可以用全名，例如 dut.x[0]")
        return

    div, unit = 1.0, timescale or "ps"
    if timescale in ("1ps", "10ps", "100ps"):
        div, unit = 1000.0, "ns"

    # 十进制显示默认按有符号补码解释（VCD 本身不带符号信息）
    use_signed = (args.radix == "dec") and not args.unsigned

    print("=" * 78)
    print("文件    : %s" % args.vcd)
    print("时间单位: %s    时间轴按 %s 显示" % (timescale or "?", unit))
    print("图形说明: 低电平=_  高电平=-  未知=x  多比特用%s%s" %
          ({"hex": "十六进制", "dec": "十进制", "bin": "二进制"}[args.radix],
           "（按有符号补码解释）" if use_signed else ""))
    print("=" * 78)
    print()

    # 十进制显示默认按有符号补码解释（VCD 本身不带符号信息）
    # --from/--to 用的是"显示单位"（通常是 ns），换算回 VCD 内部单位
    from_t = None if args.t_from is None else args.t_from * div
    to_t   = None if args.t_to   is None else args.t_to   * div

    lines, times = render(chosen, args.cols, args.radix, from_t=from_t, to_t=to_t, signed=use_signed)
    for ln in lines:
        print(ln)

    print()
    shown = ", ".join("%g" % (t / div) for t in times[:10])
    if len(times) > 10:
        shown += " ..."
    print("每列对应的时间点(%s): %s" % (unit, shown))

    # ---- 多比特信号补一张取值变化表 ----
    # 位宽大的信号（比如 40 位累加器）在图上占地方，用这张表更清楚
    buses = [s for s in chosen if s["width"] > 1 and s["changes"]]
    if buses:
        print()
        print("多比特信号的取值变化（时间 = 值）:")
        for s in buses:
            items = []
            for t, raw in s["changes"][:20]:
                items.append("%g%s=%s" % (t / div, unit, fmt_value(s, raw, args.radix, use_signed)))
            more = ""
            if len(s["changes"]) > 20:
                more = "  ...(共 %d 次变化)" % len(s["changes"])
            print("  %-16s %s%s" % (sig_label(s), "  ".join(items), more))

    print()
    print("怎么看这张图：")
    print("  1. 竖着看一列 = 同一时刻所有信号的值")
    print("  2. 横着看一行 = 一个信号随时间怎么变")
    print("  3. 找上升沿 = 某一行从 _ 变成 - 的位置")
    print("  4. 看因果   = 输出变化的位置一定比输入晚，差多少就是延迟")


if __name__ == "__main__":
    main()
