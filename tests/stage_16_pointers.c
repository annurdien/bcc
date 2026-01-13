int main() {
    int a = 10;
    int *p = &a;
    
    if (*p != 10) return 1;

    *p = 20;
    if (a != 20) return 2;

    int b = 30;
    p = &b;
    if (*p != 30) return 3;

    int **pp = &p;
    if (**pp != 30) return 4;

    return 0;
}
// RETURN: 0
