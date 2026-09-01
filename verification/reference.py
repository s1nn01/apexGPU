"""Independent Python architectural model used for differential checking."""
from __future__ import annotations

LANES = 8
REGS = 16

MNEMONICS = {
    0x0: "VNOP", 0x1: "VADD", 0x2: "VSUB", 0x3: "VMUL",
    0x4: "VMAX", 0x5: "VMIN", 0x6: "VXOR", 0x7: "VAND",
    0x8: "VSHL", 0x9: "VCMPLT", 0xA: "VABSDELTA", 0xB: "VCLAMP",
}

def u32(x: int) -> int:
    return x & 0xFFFFFFFF

def s32(x: int) -> int:
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x

def decode(word: int) -> dict:
    return {
        "mask": (word >> 56) & 0xFF,
        "op": (word >> 52) & 0xF,
        "dst": (word >> 48) & 0xF,
        "a": (word >> 44) & 0xF,
        "imm": s32((word >> 12) & 0xFFFFFFFF),
        "b": (word >> 8) & 0xF,
    }

def apply(op: int, a: int, b: int, imm: int) -> int:
    if op == 0x1: return s32(u32(a) + u32(b))
    if op == 0x2: return s32(u32(a) - u32(b))
    if op == 0x3: return s32((u32(a) * u32(b)) & 0xFFFFFFFF)
    if op == 0x4: return max(a, b)
    if op == 0x5: return min(a, b)
    if op == 0x6: return s32(u32(a) ^ u32(b))
    if op == 0x7: return s32(u32(a) & u32(b))
    if op == 0x8: return s32(u32(a) << (u32(b) & 31))
    if op == 0x9: return int(a < b)
    if op == 0xA: return s32(abs(a - b))
    if op == 0xB: return max(0, min(a, max(0, imm)))
    return a

def execute(registers: list[list[int]], word: int) -> None:
    ins = decode(word)
    if ins["op"] == 0:
        return
    old_a = registers[ins["a"]][:]
    old_b = registers[ins["b"]][:]
    out = registers[ins["dst"]][:]
    for lane in range(LANES):
        if (ins["mask"] >> lane) & 1:
            out[lane] = apply(ins["op"], old_a[lane], old_b[lane], ins["imm"])
    registers[ins["dst"]] = out
