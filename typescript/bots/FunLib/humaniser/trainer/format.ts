function Round2(x: number): number {
    return math.floor(math.abs(x) * 100 + 0.5) / 100;
}

/** Two decimals with trailing zeros trimmed: 0.10 -> "0.1", 1.00 -> "1". */
export function Sec(x: number): string {
    const text = string.format("%.2f", Round2(x));
    return string.gsub(string.gsub(text, "0+$", "")[0], "%.$", "")[0];
}

/** Like Sec, with an explicit sign. A value that rounds to zero is positive. */
export function Signed(x: number): string {
    const negative = x < 0 && Round2(x) > 0;
    return (negative ? "-" : "+") + Sec(x);
}
