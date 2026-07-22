// EXPECT:EXIT=1
#ifndef NOFLAG
int main(void) { return 1; }
#else
int main(void) { return 0; }
#endif
