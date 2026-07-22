// EXPECT:EXIT=99
void set(int *p) { *p = 99; } int main(void) { int x = 0; set(&x); return x; }
