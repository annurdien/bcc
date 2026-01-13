int main() {
    int x = 0;
    int *p = &x;
    int *q = p + 1;
    
    long addr_p = p; 
    long addr_q = q;
    
    long diff = addr_q - addr_p;
    
    if (diff != 4) return 1; 

    // Test ptr - ptr (should be scaled down)
    long ptr_diff = q - p; // Both are int*
    if (ptr_diff != 1) return 2;

    return 0;
}
// RETURN: 0
