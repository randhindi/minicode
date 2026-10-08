---
title: Front matter is hidden
---

# Markdown Preview

A **lightweight** Quick Look extension with *zero* dependencies. It handles `inline code`,
~~strikethrough~~, [links](https://example.com "Example"), autolinks like <https://apple.com>,
bare URLs such as https://github.com/foo_bar/baz_qux, and snake_case_words without italics.
Entities stay intact: &copy; 2026 &mdash; and a lone & or <3 is escaped.

Setext heading
--------------

## Lists

- First item
- Second item with **bold**
  - Nested item
  - Another nested
    1. Deep ordered
    2. Deeper
- Third item

3. Starts at three
4. Four

- [x] Done task
- [ ] Open task

Loose list:

- Paragraph one

- Paragraph two
  continues here

## Code

```swift
// Greets someone
struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)! #\(42)" }
}
```

```python
def fib(n: int) -> int:
    """Return the nth Fibonacci number."""
    return n if n < 2 else fib(n - 1) + fib(n - 2)  # recursive
```

```diff
- old line
+ new line
```

    indented code block

## Tables

| Name | Size | Notes |
|:-----|-----:|:-----:|
| `a|b` | 1.2 KB | centered |
| beta | 42 | **bold** |

## Quotes

> A blockquote with *emphasis*
> and a second line.
>
> > Nested quote.

> [!WARNING]
> GitHub-style alerts work too.

---

![Alt text](https://example.com/img.png) and a [reference link][ref].

<details><summary>Raw HTML</summary>Inline <kbd>⌘</kbd> + <kbd>Space</kbd></details>

Line ending with two spaces  
forces a break. Escaped \*stars\* stay literal.

[ref]: https://example.com/ref "Reference"

## Math

Inline math like $E = mc^2$ and $`\sqrt{x_i}`$, but prices like $5 and $10 stay text.

```math
c \;=\; \sum_{i=1}^{n} \frac{\varepsilon_i}{2} \;-\; \frac{q}{4N}
```

$$
\sigma^2_{\mathrm{MS}} \;=\; n\left(\frac{1}{24\,q^{2}} + \frac{1}{48\,(2N)^{2}}\right)
$$

Broken TeX shows inline: $\frac{1}{$.

```latex
\sigma^2 = \frac{1}{12}
```

```latex
\documentclass{article}
\begin{document}Not math\end{document}
```
