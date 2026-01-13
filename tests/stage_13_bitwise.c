// RETURN: 0
int main() {
    int a = 12; // 1100
    int b = 10; // 1010
    
    // AND: 1100 & 1010 = 1000 (8)
    if ((a & b) != 8) return 1;

    // OR: 1100 | 1010 = 1110 (14)
    if ((a | b) != 14) return 2;

    // XOR: 1100 ^ 1010 = 0110 (6)
    if ((a ^ b) != 6) return 3;

    // Shift Left: 1100 << 1 = 11000 (24)
    if ((a << 1) != 24) return 4;
    
    // Shift Right: 1100 >> 1 = 0110 (6)
    if ((a >> 1) != 6) return 5;
    return 0;
}
