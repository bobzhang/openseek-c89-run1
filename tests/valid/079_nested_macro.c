// EXPECT:EXIT=12
#define DOUBLE(x) ((x)+(x))
#define QUAD(x) DOUBLE(DOUBLE(x))
int main(void) { return QUAD(3); }
