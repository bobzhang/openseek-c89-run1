// EXPECT:EXIT=20
int main(void) { int x = 0; if (0) x = 10; else x = 20; return x; }
