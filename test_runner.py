import os
import subprocess
import sys
import re
from pathlib import Path

# Get the macOS SDK path once at the start
try:
    sdk_path = subprocess.run("xcrun --show-sdk-path", shell=True, capture_output=True, text=True).stdout.strip()
except:
    sdk_path = "" # Fallback or handle linux later

def run_command(command):
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result
    except subprocess.CalledProcessError as e:
        return e

def test_file(filepath, expected_return_code, index, total):
    print(f"[{index}/{total}] Testing {filepath}...", end=" ", flush=True)
    
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
    sysroot_flag = f"-isysroot {sdk_path}" if sdk_path else ""
    cmd3 = f"clang -arch x86_64 {sysroot_flag} {object_file} -o {executable}"
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

def scan_tests_in_dir(directory):
    discovered_tests = []
    # Walk directory to find .c files
    if not os.path.exists(directory):
        return []
        
    for filename in os.listdir(directory):
        if not filename.endswith(".c"):
            continue
            
        filepath = os.path.join(directory, filename)
        with open(filepath, 'r') as f:
            content = f.read()
            # Look for // RETURN: {int}
            match = re.search(r"//\s*RETURN:\s*(\d+)", content)
            if match:
                expected_code = int(match.group(1))
                discovered_tests.append((filepath, expected_code))
                
    return discovered_tests

def main():
    # Build compiler first
    print("Building compiler...", flush=True)
    if subprocess.run("swift build", shell=True).returncode != 0:
        print("Compiler build failed.")
        sys.exit(1)
        
    # Discovery
    final_tests = scan_tests_in_dir("tests")
    
    # Sort for consistent output
    final_tests.sort(key=lambda x: x[0])
    
    passed = 0
    total = len(final_tests)
    for i, (test_path, expected) in enumerate(final_tests, 1):
        if test_file(Path(test_path), expected, i, total):
            passed += 1
            
    print(f"\n{passed}/{len(final_tests)} tests passed.")
    if passed != len(final_tests):
        sys.exit(1)

if __name__ == "__main__":
    main()
