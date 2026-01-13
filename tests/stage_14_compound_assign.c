int main() {
    int a = 10;
    a += 5; // 15
    if (a != 15) return 1;

    a -= 5; // 10
    if (a != 10) return 2;

    a *= 2; // 20
    if (a != 20) return 3;

    a /= 2; // 10
    if (a != 10) return 4;
    
    a %= 3; // 1
    if (a != 1) return 5;

    int b = 3; // 0011
    b <<= 2; // 12 (1100)
    if (b != 12) return 6;

    b >>= 2; // 3 (0011)
    if (b != 3) return 7;

    b &= 1; // 1
    if (b != 1) return 8;

    b |= 2; // 3
    if (b != 3) return 9;

    b ^= 3; // 0
    if (b != 0) return 10;

    return 0; // Success
}
// RETURN: 0
