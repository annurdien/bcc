// RETURN: 0
int foo() {
    static int x = 5;
    x = x + 1;
    return x;
}

int main() {
    if (foo() != 6) return 1;
    if (foo() != 7) return 2;
    if (foo() != 8) return 3;
    
    // Check that we can have another static with same name in different scope
    static int x = 100;
    if (x != 100) return 4;
    
    return 0;
}
