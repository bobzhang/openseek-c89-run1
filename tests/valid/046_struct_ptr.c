// EXPECT:EXIT=20
struct S { int a; }; int main(void) { struct S s; struct S *p = &s; p->a = 20; return p->a; }
