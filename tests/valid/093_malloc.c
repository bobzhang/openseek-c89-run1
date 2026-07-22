// EXPECT:EXIT=0
void *malloc(int sz); void free(void *p);
int main(void) { void *p = malloc(16); free(p); return 0; }
