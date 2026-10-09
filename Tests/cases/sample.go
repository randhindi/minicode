package main

import (
	"fmt"
	"strings"
)

// Shout upper-cases s.
func Shout(s string) string { return strings.ToUpper(s) + "!" }

type Point struct{ X, Y int }

func main() {
	ch := make(chan int, 3)
	defer close(ch)
	fmt.Println(Shout(`raw`), len("abc"), 'x', nil == nil, Point{1, 2})
}
