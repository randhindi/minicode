#include <stdio.h>
#define MAX 16

/* Sum an array. */
static int sum(const int *xs, size_t n) {
    int total = 0;
    for (size_t i = 0; i < n; i++) total += xs[i];
    return total;
}

int main(void) {
    int xs[MAX] = {1, 2, 3};
    printf("%d\n", sum(xs, 3));
    return NULL == 0 ? 0 : 1;
}
