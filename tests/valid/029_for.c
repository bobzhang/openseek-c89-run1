// EXPECT:EXIT=10
int main(void) { int i; int s = 0; for (i = 0; i < 5; i = i + 1) s = s + 2; return s; }
