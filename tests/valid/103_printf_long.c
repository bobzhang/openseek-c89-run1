// EXPECT:EXIT=0
int printf(const char *f, ...);
int main(void) { long x = 42; printf("%ld", x); return 0; }
