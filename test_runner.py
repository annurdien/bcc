import os
import subprocess
import sys
from pathlib import Path

def run_command(command):
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result
    except subprocess.CalledProcessError as e:
        return e

def test_file(filepath, expected_return_code):
    print(f"Testing {filepath}...", end=" ")
    
    filename = filepath.stem
    executable = f"./tests/{filename}"
    
    # 1. Compile
    compile_cmd = f"make {executable}"
    
    # Because our Makefile target is generic, we might need a specific way to call it or rely on the python script to run the compiler
    # Let's rely on the python script to invoke the compiler binary directly to be safe and cleaner
    
    compiler = ".build/debug/bcc"
    assembly_file = filepath.with_suffix(".s")
    
    # Run Compiler
    cmd1 = f"{compiler} {filepath} > {assembly_file}"
    result = subprocess.run(cmd1, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        print("FAILED (Compilation)")
        print(result.stderr.decode())
        return False

    # Assemble
    object_file = filepath.with_suffix(".o")
    cmd2 = f"as -arch x86_64 {assembly_file} -o {object_file}"
    if subprocess.run(cmd2, shell=True).returncode != 0:
        print("FAILED (Assembly)")
        return False

    # Link
    cmd3 = f"clang -arch x86_64 {object_file} -o {executable}"
    if subprocess.run(cmd3, shell=True).returncode != 0:
        print("FAILED (Linking)")
        return False
        
    # Run
    try:
        subprocess.run(executable, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return_code = 0 
    except subprocess.CalledProcessError as e:
        return_code = e.returncode
        
    # Check result
    if return_code == expected_return_code:
        print("PASSED")
        # Cleanup
        os.remove(assembly_file)
        os.remove(object_file)
        os.remove(executable)
        return True
    else:
        print(f"FAILED (Expected {expected_return_code}, got {return_code})")
        return False

def main():
    # Build compiler first
    print("Building compiler...")
    if subprocess.run("swift build", shell=True).returncode != 0:
        print("Compiler build failed.")
        sys.exit(1)
        
    tests = [
        ("tests/valid_bang_0.c", 1),
        ("tests/valid_bang_5.c", 0),
        ("tests/valid_bang_nested.c", 1),
        ("tests/valid_add.c", 3),
        ("tests/valid_sub.c", 255), # -1 becomes 255 (unsigned byte return code)
        ("tests/valid_mul.c", 6),
        ("tests/valid_div.c", 5),
        ("tests/valid_precedence_1.c", 14),
        ("tests/valid_precedence_2.c", 20),
    ]
    
    passed = 0
    for test_path, expected in tests:
        if test_file(Path(test_path), expected):
            passed += 1
            
    print(f"\n{passed}/{len(tests)} tests passed.")
    if passed != len(tests):
        sys.exit(1)

if __name__ == "__main__":
    main()
