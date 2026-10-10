#pragma once

#include <cstdio>
#include <cstdlib>

// Minimal assertion helper; the tests are plain executables so `make test` needs
// nothing beyond the compiler.
inline int g_check_failures = 0;

#define CHECK(expr)                                                                   \
    do {                                                                              \
        if (!(expr)) {                                                                \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr);      \
            ++g_check_failures;                                                       \
        }                                                                             \
    } while (0)

#define CHECK_EQ(a, b) CHECK((a) == (b))

inline int check_summary(const char* name) {
    if (g_check_failures) {
        std::fprintf(stderr, "%s: %d failure(s)\n", name, g_check_failures);
        return 1;
    }
    std::printf("%s: ok\n", name);
    return 0;
}
