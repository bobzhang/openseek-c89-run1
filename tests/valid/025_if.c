// EXPECT:EXIT=10
int main(void) { int x = 0; if (1) x = 10; else x = 20; return x; }
