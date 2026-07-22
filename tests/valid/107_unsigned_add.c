// EXPECT:EXIT=15
unsigned int add(unsigned int a, unsigned int b) { return a + b; }
int main(void) { return (int)add(7, 8); }
