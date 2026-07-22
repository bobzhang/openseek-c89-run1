// EXPECT:EXIT=123
int counter(void) { static int c = 0; c = c + 1; return c; }
int main(void) { int a = counter(); int b = counter(); int c = counter(); return a * 100 + b * 10 + c; }
