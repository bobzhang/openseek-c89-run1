// EXPECT:EXIT=10
#if 1
int main(void) { return 10; }
#else
int main(void) { return 20; }
#endif
