COMPILER = .build/debug/bcc

SRC = valid.c

TARGET = valid

.PHONY: all test run clean

all: test

$(COMPILER):
	@echo "Building compiler..."
	@swift build

$(TARGET).s: $(COMPILER) $(SRC)
	@echo "Generating assembly..."
	@$(COMPILER) $(SRC) > $(TARGET).s

$(TARGET).o: $(TARGET).s
	@echo "Assembling..."
	@as $(TARGET).s -o $(TARGET).o

$(TARGET): $(TARGET).o
	@echo "Linking..."
	@clang -target x86_64 $(TARGET).o -o $(TARGET)

test: $(TARGET)
	@echo "Running test for $(SRC)..."
	@./$(TARGET) || true
	@echo "Test finished with exit code: $?"

run: $(COMPILER) $(SRC)
	@echo "Running compiler and printing assembly..."
	@$(COMPILER) $(SRC)

clean:
	@echo "Cleaning up..."
	@rm -f $(TARGET) $(TARGET).o $(TARGET).s