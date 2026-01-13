int main() {
    int a = 5;
    int b = ++a; // a is 6, b is 6
    if (a != 6) return 1;
    if (b != 6) return 2;

    int c = a++; // c is 6, a is 7
    if (c != 6) return 3;
    if (a != 7) return 4;

    int d = --a; // a is 6, d is 6
    if (a != 6) return 5;
    if (d != 6) return 6;

    int e = a--; // e is 6, a is 5
    if (e != 6) return 7;
    if (a != 5) return 8;

    return 0;
}
// RETURN: 0
