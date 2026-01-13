// RETURN: 0
int main() {
    unsigned int a = 1;
    unsigned int b = 2;
    if (a - b > 0) { // 1 - 2 = 4294967295 (on 32-bit arithmetic), which is > 0
        return 0; // Success
    }
    return 1; // Fail
}
