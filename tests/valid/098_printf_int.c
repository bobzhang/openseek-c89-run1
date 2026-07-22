// EXPECT:EXIT=0
int printf(const char *f, ...); int main(void) { printf("x=%d", 42); return 0; }
