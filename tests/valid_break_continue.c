// RETURN: 4
int main() {
    int sum = 0;
    // Nesting, break, and continue
    for (int i = 0; i < 10; i = i + 1) {
        if (i == 0) continue;
        if (i == 5) break;
        sum = sum + 1;
    }
    return sum; // i=1,2,3,4. sum=4.
}
