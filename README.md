# transpiler

An little expression transpiler. It is capable of generating:
- value literals (ints, strings, booleans) and variables
- lists
- lambda expressions and function applications
- let expressions
- binary operations
- match expressions with pattern matching

Pattern matching currently supports matching against:
- literals
- lists with optional tails
- pattern variables

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
