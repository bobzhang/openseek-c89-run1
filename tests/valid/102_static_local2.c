// EXPECT:EXIT=42
int get_next(void) { static int x = 41; x = x + 1; return x; }
int main(void) { return get_next(); }
