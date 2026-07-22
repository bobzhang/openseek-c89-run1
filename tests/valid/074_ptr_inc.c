// EXPECT:EXIT=5
int main(void) { int x = 4; int *p = &x; (*p)++; return x; }
