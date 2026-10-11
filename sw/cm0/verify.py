#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify.py —— 把 Cortex-M0 串口打印的 FIR 结果和黄金模型比对

用法：
  python verify.py            # 读 09_soc_cm0/uart_capture.txt 和 expected.txt
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOC_DIR = os.path.join(ROOT, "09_soc_cm0")

def main():
    cap = open(os.path.join(SOC_DIR, "uart_capture.txt"), "r", errors="replace").read()
    exp = [l.strip() for l in open(os.path.join(SOC_DIR, "expected.txt"))
           if l.strip()]

    # 抓取 BEGIN 和 END 之间的结果行
    if "FIR_RESULT_BEGIN" not in cap or "FIR_RESULT_END" not in cap:
        print("FAIL: 串口输出里没有找到 FIR_RESULT_BEGIN/END 标记")
        print("---- 串口原始输出 ----")
        print(cap)
        return 1

    body = cap.split("FIR_RESULT_BEGIN")[1].split("FIR_RESULT_END")[0]
    got = [l.strip() for l in body.split() if l.strip()]

    n = min(len(got), len(exp))
    bad = 0
    for i in range(n):
        if got[i].upper() != exp[i].upper():
            bad += 1
            if bad <= 10:
                print("  MISMATCH[%d]: M0=%s 参考=%s" % (i, got[i], exp[i]))

    print("M0 打印 %d 个结果，黄金模型 %d 个" % (len(got), len(exp)))
    if bad == 0 and len(got) == len(exp):
        print("===== PASS: Cortex-M0 跑出的 FIR 结果与软件黄金模型逐位一致 =====")
        return 0
    else:
        print("===== FAIL: %d 个不一致（或数量对不上）=====" % bad)
        return 1

if __name__ == "__main__":
    sys.exit(main())
