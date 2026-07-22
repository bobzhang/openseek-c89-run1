// EXPECT:EXIT=0
int printf(const char *f, ...); int main(void) { printf("%d %d", 1, 2); return 0; }
