// EXPECT:EXIT=1
#define FLAG
#ifdef FLAG
int main(void) { return 1; }
#else
int main(void) { return 0; }
#endif
