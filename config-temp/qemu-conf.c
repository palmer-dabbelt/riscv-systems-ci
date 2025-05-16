
#ifdef __linux__
#  define THREAD __thread
#else
#  define THREAD
#endif
static THREAD int tls_var;
int main(void) { return tls_var; }
