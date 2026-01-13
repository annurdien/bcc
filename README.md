### BCC (Bakpia C Compiler)

*My implementation of a C compiler for x64 processors.*

*Reference: Writing a C Compiler — Build a Real Programming Language from Scratch by Nora Sandler*

### Checkpoint (Jan 7, 2026)
- [x] Stage 1 - Minimal C Program (function decl, return constant)
- [x] Stage 2 - Unary Operators
    - [x] Negation (`-`)
    - [x] Bitwise Complement (`~`)
    - [x] Logical Negation (`!`)
- [x] Stage 3 - Binary Operators
    - [x] Addition (`+`)
    - [x] Subtraction (`-`)
    - [x] Multiplication (`*`)
    - [x] Division (`/`)
- [x] Stage 4 - Relational & Logical Operators
    - [x] Relational (`<, >, <=, >=`)
    - [x] Equality (`==, !=`)
    - [x] Logical AND (`&&`)
    - [x] Logical OR (`||`)
- [x] Stage 5 - Local Variables & Assignment
    - [x] Variable Declaration (`int x = ...`)
    - [x] Variable Usage (`return x`)
    - [x] Assignment (`x = y`)
- [x] Stage 6 - Conditionals
    - [x] If Statements (`if (cond) { ... } else { ... }`)
    - [x] Conditional Operator (`cond ? true : false`)
    - [x] Compound Statements / Blocks (`{ ... }`)
- [x] Stage 7 - Loops
    - [x] While (`while`)
    - [x] Do-While (`do ... while`)
    - [x] For (`for`)
    - [x] Break (`break`)
    - [x] Continue (`continue`)
- [x] Stage 8 - Functions
    - [x] Function Function Definition & Calling (Multi-argument)
    - [x] System V ABI (Arguments in registers)
- [x] Stage 9 - Global Variables
    - [x] Global Variable Declaration
    - [x] Global vs Local Scope (Shadowing)
- [x] Stage 10 - Static Variables
    - [x] Static Global Variables (Internal Linkage)
    - [x] Static Local Variables (Persistence)
- [x] Stage 11 - Long Integers
    - [x] 64-bit Integer type (`long`)
    - [x] Type Promotion
- [x] Stage 12 - Unsigned Integers
    - [x] Unsigned types (`unsigned int`, `unsigned long`)
    - [x] Unsigned Arithmetic & Comparison
- [x] Stage 13 - Bitwise Operators
    - [x] AND (`&`)
    - [x] OR (`|`)
    - [x] XOR (`^`)
    - [x] Shift Left (`<<`)
    - [x] Shift Right (`>>`)
- [x] Stage 14 - Compound Assignment
    - [x] Arithmetic Compound (`+=`, `-=`, `*=`, `/=`, `%=`)
    - [x] Bitwise Compound (`&=`, `|=`, `^=`, `<<=`, `>>=`)
- [x] Stage 15 - Increment & Decrement
    - [x] Pre-increment (`++x`)
    - [x] Post-increment (`x++`)
    - [x] Pre-decrement (`--x`)
    - [x] Post-decrement (`x--`)





### Test System
![CI](https://github.com/annurdien/bcc/actions/workflows/ci.yml/badge.svg)
The test runner `test_runner.py` supports **Automatic Test Discovery**.
- Add a `.c` file to `tests/`.
- Include `// RETURN: <expected_code>` in the file.
- `make test-all` will automatically compile, run, and verify the exit code.



