// EXPECT:EXIT=250
int main(void) { unsigned char x = 5; return ~x & 255; }
