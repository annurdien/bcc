// RETURN: 0
long foo() {
    long x = 4294967296 + 10; // 2^32 + 10. Truncated to 32-bit = 10.
    return x;
}

int main() {
    if (foo() == 10) return 1; // If truncated, it equals 10 => Fail.
    if (foo() > 100) return 0; // Correct behavior
    return 2;
}
