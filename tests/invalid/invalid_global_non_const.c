int x = foo(); // FAIL: Initializer must be constant

int foo() {
    return 5;
}

int main() {
    return x;
}