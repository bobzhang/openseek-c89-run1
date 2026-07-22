// EXPECT:EXIT=4
int main(void) { int i, s = 0; for (i = 0; i < 5; i = i + 1) { if (i == 3) continue; s = s + 1; } return s; }
