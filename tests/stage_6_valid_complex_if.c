// RETURN: 1
int main() {
    int ret = 0;

    // 1. Basic If (True)
    if (1) ret = ret + 1; // ret = 1

    // 2. Basic If (False)
    if (0) ret = 100;    // ret = 1

    // 3. If-Else (True)
    if (5 > 4) 
        ret = ret + 1;   // ret = 2
    else 
        ret = 666;

    // 4. If-Else (False)
    if (5 < 4)
        ret = 777;
    else
        ret = ret + 1;   // ret = 3

    // 5. Ternary (True)
    ret = (1 ? ret + 1 : 0); // ret = 4

    // 6. Ternary (False)
    ret = (0 ? 0 : ret + 1); // ret = 5

    // 7. Nested If
    if (1) {
        if (0) {
            ret = 888;
        } else {
            if (1) ret = ret - 4; // ret = 1
        }
    }

    return ret; 
}
