// EXPECT:EXIT=1
int main(void) { int x = 0; do { x = 1; } while (0); return x; }
