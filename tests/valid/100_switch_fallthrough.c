// EXPECT:EXIT=12
int main(void) { int x = 0; switch (1) { case 1: x = x + 5; case 2: x = x + 7; break; default: x = 100; } return x; }
