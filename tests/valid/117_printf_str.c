// EXPECT:EXIT=0
int printf(const char *f, ...); int main(void) { printf("%s", "test"); return 0; }
