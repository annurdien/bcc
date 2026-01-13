int g_var = 10;
int uninit_var; 

int main() {
    g_var = g_var + 5;
    uninit_var = 2;
    return g_var + uninit_var; // 15 + 2 = 17
}
// RETURN: 17