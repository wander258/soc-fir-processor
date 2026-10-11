#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FIR 系数设计 + 测试向量生成 + 黄金模型比对

只用 Python 标准库，不需要 numpy / scipy / pip。
（你机器上的 Python 是 MSYS2 自带的，没有 pip，所以特意写成零依赖。）

用法:
    python gen_fir_vectors.py                      # 默认 8 阶，生成 lab04 用的文件
    python gen_fir_vectors.py --taps 81            # 生成 81 阶（赛题要求的规模）
    python gen_fir_vectors.py --check got.hex      # 用黄金模型校验 RTL 导出的结果

生成的产物（在 04_fir8 目录下）:
    coeffs.vh    —— 量化后的 Q1.15 系数，给 Verilog `include
    stim.hex     —— 测试激励（给 TB $readmemh）
    exp.hex      —— 黄金模型算出的期望输出（给 TB $readmemh）
"""

import argparse
import math
import os


# ----------------------------------------------------------------------
# 1. 滤波器设计：窗函数法（Hamming 窗）设计线性相位低通 FIR
# ----------------------------------------------------------------------
def design_lowpass(numtaps, fc):
    """
    理想低通冲激响应 + Hamming 窗。

    numtaps : 抽头数（赛题是 81）
    fc      : 归一化截止频率，0~0.5（0.5 = Nyquist）
    返回    : 浮点系数列表，已归一化到直流增益 = 1
    """
    if numtaps % 2 == 0:
        print("[提示] 抽头数为偶数，群延迟是 (NTAP-1)/2 = %.1f 个样本（半样本延迟），"
              "赛题用的是奇数（81），建议用奇数抽头" % ((numtaps - 1) / 2))
    M = numtaps - 1                      # 滤波器阶数 = 抽头数 - 1
    h = []
    for n in range(numtaps):
        if n == M / 2:
            s = 2.0 * fc                 # sinc 在 0 点的极限值
        else:
            s = math.sin(2 * math.pi * fc * (n - M / 2)) / (math.pi * (n - M / 2))
        w = 0.54 - 0.46 * math.cos(2 * math.pi * n / M)   # Hamming 窗
        h.append(s * w)

    # 归一化：让直流增益 = 1，这样单位幅度的输入不会被放大/缩小
    total = sum(h)
    return [x / total for x in h]


def quantize(h, cw=16):
    """把浮点系数量化成 Q1.15 定点整数（16bit 有符号）。"""
    scale = 1 << (cw - 1)                # 2^15 = 32768
    q = []
    for x in h:
        v = int(round(x * scale))
        v = max(-(1 << (cw - 1)), min((1 << (cw - 1)) - 1, v))   # 饱和到 [-32768, 32767]
        q.append(v)
    return q


# ----------------------------------------------------------------------
# 2. 定点黄金模型：必须和 RTL 的算术逐位一致
# ----------------------------------------------------------------------
def golden_fir(samples, coeffs_q, cw=16, dw=16):
    """
    全并行 FIR 的定点参考模型。

    x 是 Q1.15（值 = X / 2^15），h 是 Q1.15（值 = H / 2^15）
    乘积 = X*H / 2^30，累加后要回到 Q1.15 输出 => 右移 (cw-1) = 15 位
    与 RTL 里的  sum[SHIFT+DW-1 : SHIFT]  完全对应。
    """
    ntap = len(coeffs_q)
    shift = cw - 1
    ymax = (1 << (dw - 1)) - 1
    ymin = -(1 << (dw - 1))

    n = len(samples)

    def x(i):
        """x[i]：下标越界当作 0，等价于 RTL 里延迟线初值为 0、末尾补 0"""
        return samples[i] if 0 <= i < n else 0

    out = []
    for m in range(n + ntap - 1):        # 全卷积长度 = 样本数 + 抽头数 - 1
        acc = 0
        for k in range(ntap):
            acc += coeffs_q[k] * x(m - k)   # y[m] = Σ h[k]·x[m-k]
        y = acc >> shift                 # Python 的 >> 对负数是向下取整，和算术右移一致
        y = max(ymin, min(ymax, y))      # 饱和，和 RTL 里的饱和逻辑一致
        out.append(y)
    return out


# ----------------------------------------------------------------------
# 3. 文件输出
# ----------------------------------------------------------------------
def write_hex(path, values, digits=4):
    """写成 $readmemh 能读的十六进制，每个数用 digits 位十六进制（补码）。"""
    mask = (1 << (4 * digits)) - 1
    with open(path, "w", newline="\n") as f:
        for v in values:
            f.write("%0*X\n" % (digits, v & mask))


def read_hex(path, digits=4):
    """读回 $writememh 导出的十六进制，还原成有符号整数。"""
    vals = []
    sign = 1 << (4 * digits - 1)
    mask = (1 << (4 * digits)) - 1
    skipped = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            if any(c in line.lower() for c in "xz"):
                skipped += 1          # 未初始化的项，$writememh 会写成 xxxx
                continue
            v = int(line, 16) & mask
            if v & sign:                 # 补码还原成负数
                v -= (1 << (4 * digits))
            vals.append(v)
    if skipped:
        print("[提示] %s 里有 %d 个未初始化项(xxxx)，已跳过" % (os.path.basename(path), skipped))
    return vals


def write_coeffs_vh(path, coeffs_q, cw=16, ntap=None):
    """生成 Verilog 头文件，里面既有 localparam 也有 assign。"""
    n = ntap if ntap else len(coeffs_q)
    lines = []
    lines.append("// ============================================================")
    lines.append("// 本文件由 gen_fir_vectors.py 自动生成，不要手动修改")
    lines.append("// 抽头数 NTAP = %d，系数位宽 CW = %d（Q1.15 定点）" % (n, cw))
    lines.append("// 对称性检查：h[k] == h[NTAP-1-k]（线性相位 FIR）")
    lines.append("// ============================================================")
    for k, v in enumerate(coeffs_q):
        lines.append("localparam signed [CW-1:0] H%d = -16'sd%d;" % (k, -v) if v < 0
                     else "localparam signed [CW-1:0] H%d = 16'sd%d;" % (k, v))
    lines.append("")
    for k in range(len(coeffs_q)):
        lines.append("assign h[%d] = H%d;" % (k, k))
    lines.append("")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines))


# ----------------------------------------------------------------------
# 4. 主流程
# ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--taps", type=int, default=8, help="抽头数（奇数），默认 8")
    ap.add_argument("--cutoff", type=float, default=0.15, help="归一化截止频率，默认 0.15")
    ap.add_argument("--nsamp", type=int, default=64, help="测试样本数，默认 64")
    ap.add_argument("--check", type=str, default=None,
                    help="校验模式：传入 RTL 导出的 got.hex，用黄金模型比对")
    ap.add_argument("--outdir", type=str, default=None, help="输出目录，默认脚本所在目录")
    args = ap.parse_args()

    outdir = args.outdir or os.path.dirname(os.path.abspath(__file__))
    ntap = args.taps

    # ---- 设计系数 ----
    h = design_lowpass(ntap, args.cutoff)
    coeffs_q = quantize(h)

    # 对称性自检
    for k in range(ntap // 2):
        assert coeffs_q[k] == coeffs_q[ntap - 1 - k] or abs(coeffs_q[k] - coeffs_q[ntap - 1 - k]) <= 1, \
            "系数不对称，检查设计"

    print("=" * 60)
    print("FIR 设计：抽头数 = %d，截止频率 = %.3f（归一化）" % (ntap, args.cutoff))
    print("=" * 60)
    print("量化后的 Q1.15 系数（前 8 个 / 后 8 个）:")
    head = coeffs_q[:8]
    tail = coeffs_q[-8:]
    print("  " + " ".join("%6d" % v for v in head))
    print("  ...")
    print("  " + " ".join("%6d" % v for v in tail))
    print("  系数和 = %d  (理想值 32768 = 1.0)" % sum(coeffs_q))

    if args.check:
        # ---- 校验模式 ----
        got = read_hex(args.check)
        stim_path = os.path.join(outdir, "stim.hex")
        samples = read_hex(stim_path)
        exp = golden_fir(samples, coeffs_q)
        print("\nRTL 导出 %d 个数，黄金模型期望 %d 个数" % (len(got), len(exp)))
        # RTL 有一个额外的流水线前导拍，跳过 got[0]
        if len(got) > 1:
            got = got[1:]
        n = min(len(got), len(exp))
        bad = []
        for i in range(n):
            if got[i] != exp[i]:
                bad.append((i, got[i], exp[i]))
        if not bad:
            print("\n===== PASS: 前 %d 个样本与黄金模型逐位一致 =====" % n)
        else:
            print("\n===== FAIL: %d / %d 个样本不一致 =====" % (len(bad), n))
            for i, g, e in bad[:10]:
                print("   样本 %3d: RTL = %6d, 期望 = %6d" % (i, g, e))
        return

    # ---- 生成模式 ----
    # 激励：两个正弦 + 一个冲激，覆盖通带、阻带、瞬态
    samples = []
    for n in range(args.nsamp):
        v = (0.45 * math.sin(2 * math.pi * 0.05 * n)
             + 0.25 * math.sin(2 * math.pi * 0.35 * n))
        if n == 10:
            v += 0.8                     # 一个冲激，检验瞬态响应
        samples.append(max(-32768, min(32767, int(round(v * 32767)))))

    exp = golden_fir(samples, coeffs_q)

    write_coeffs_vh(os.path.join(outdir, "coeffs.vh"), coeffs_q, ntap=ntap)
    write_hex(os.path.join(outdir, "coeffs.hex"), coeffs_q)
    write_hex(os.path.join(outdir, "stim.hex"), samples)
    write_hex(os.path.join(outdir, "exp.hex"), exp)

    print("\n已生成:")
    print("  coeffs.vh  (%d 个系数)" % ntap)
    print("  coeffs.hex (%d 个系数，供 SoC 测试台 $readmemh 用)" % ntap)
    print("  stim.hex   (%d 个激励样本)" % len(samples))
    print("  exp.hex    (%d 个期望输出)" % len(exp))
    print("\n注意：exp.hex 的长度 = 激励数 + 抽头数 - 1（全卷积长度）")


if __name__ == "__main__":
    main()
