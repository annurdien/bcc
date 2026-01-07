COMPILER = .build/debug/bcc
SRC = valid.c
TARGET = valid

.PHONY: all test run clean tokens ast tacky compiler asm bin

all: test

# --- Primary Build Targets ---

# Build the compiler executable
$(COMPILER):
	@echo "Building compiler..."
	@swift build

# Build the final binary executable
$(TARGET): $(TARGET).o
	@echo "Linking..."
	@clang -arch x86_64 $(TARGET).o -o $(TARGET)

# Build the object file from the assembly
$(TARGET).o: $(TARGET).s
	@echo "Assembling..."
	@as -arch x86_64 $(TARGET).s -o $(TARGET).o

# Build the assembly file from the source
$(TARGET).s: $(COMPILER) $(SRC)
	@echo "Generating assembly..."
	@$(COMPILER) $(SRC) > $(TARGET).s

# --- Testing & Utility Targets ---

# Run the full, end-to-end test (compile, link, run)
test: $(TARGET)
	@echo "Running test for $(SRC)..."
	@./$(TARGET) || true
	@echo "Test finished with exit code: $?"

# Run all tests using the python runner
test-all: $(COMPILER)
	@python3 test_runner.py

# Test just the lexer by printing tokens
tokens: $(COMPILER)
	@echo "--- Printing Tokens ---"
	@$(COMPILER) --print-tokens $(SRC)

# Test just the parser by printing the AST
ast: $(COMPILER)
	@echo "--- Printing AST ---"
	@$(COMPILER) --print-ast $(SRC)

# NEW: Test the TACKY generator by printing TACKY IR
tacky: $(COMPILER)
	@echo "--- Printing TACKY ---"
	@$(COMPILER) --print-tacky $(SRC)

# "Meta-target" to just build the compiler
compiler: $(COMPILER)
	@echo "Compiler is built."

# "Meta-target" to just build the assembly file
asm: $(TARGET).s
	@echo "Assembly file $(TARGET).s is generated."

asm-ast: $(COMPILER)
	@echo "--- Printing Assembly AST ---"
	@$(COMPILER) --print-asm-ast $(SRC)

# "Meta-target" to just build the final binary
bin: $(TARGET)
	@echo "Binary executable $(TARGET) is built."

# Run the compiler and print assembly directly to the terminal
run: $(COMPILER) $(SRC)
	@echo "Running compiler and printing assembly..."
	@$(COMPILER) $(SRC)

# Clean up all build artifacts
clean:
	@echo "Cleaning up..."
	@rm -f $(TARGET) $(TARGET).o $(TARGET).s
	@echo "Cleaning build directory..."
	@rm -rf .build