// EXPECT:EXIT=42
int get42(void) { return 42; } int main(void) { int (*f)(void) = get42; return f(); }
