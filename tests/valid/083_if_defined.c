// EXPECT:EXIT=1
#define X
#if defined(X)
int main(void) { return 1; }
#else
int main(void) { return 0; }
#endif
