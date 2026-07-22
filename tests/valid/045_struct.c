// EXPECT:EXIT=10
struct S { int a; int b; }; int main(void) { struct S s; s.a = 10; return s.a; }
