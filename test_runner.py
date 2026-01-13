#!/usr/bin/env python3
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

def test_file(filepath, expected_return_code, expect_fail, index, total):
    print(f"[{index}/{total}] Testing {filepath}...", end=" ", flush=True)
    
    filepath_obj = Path(filepath)
    filename = filepath_obj.stem
    executable = filepath_obj.parent / filename
    
    # 1. Compile
    compiler = ".build/debug/bcc"
    assembly_file = filepath_obj.with_suffix(".s")
    
    # Run Compiler
    cmd1 = f"{compiler} {filepath} > {assembly_file}"
    result = subprocess.run(cmd1, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    if expect_fail:
        if result.returncode != 0:
            print("PASSED (Expected Fail)")
            if assembly_file.exists():
                os.remove(assembly_file)
            return True
        else:
            print("FAILED (Expected Compilation Error, but succeeded)")
            # Clean up artifacts if it surprisingly succeeded
            if assembly_file.exists():
                os.remove(assembly_file)
            return False

    # Positive Case
    if result.returncode != 0:
        print("FAILED (Compilation)")
        print(result.stderr.decode())
        if assembly_file.exists():
            os.remove(assembly_file)
        return False

    # Assemble
    object_file = filepath_obj.with_suffix(".o")
    cmd2 = f"as -arch x86_64 {assembly_file} -o {object_file}"
    if subprocess.run(cmd2, shell=True).returncode != 0:
        print("FAILED (Assembly)")
        if assembly_file.exists(): os.remove(assembly_file)
        if object_file.exists(): os.remove(object_file)
        return False

    # Link
    sysroot_flag = f"-isysroot {sdk_path}" if sdk_path else ""
    cmd3 = f"clang -arch x86_64 {sysroot_flag} {object_file} -o {executable}"
    if subprocess.run(cmd3, shell=True).returncode != 0:
        print("FAILED (Linking)")
        if assembly_file.exists(): os.remove(assembly_file)
        if object_file.exists(): os.remove(object_file)
        return False
        
    # Run
    try:
        subprocess.run(str(executable), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return_code = 0 
    except subprocess.CalledProcessError as e:
        return_code = e.returncode
    except OSError as e:
        print(f"FAILED (Execution error: {e})")
        return_code = -1
        
    # Cleanup
    if assembly_file.exists(): os.remove(assembly_file)
    if object_file.exists(): os.remove(object_file)
    if executable.exists(): os.remove(executable)

    # Check result
    if return_code == expected_return_code:
        print("PASSED")
        return True
    else:
        print(f"FAILED (Expected {expected_return_code}, got {return_code})")
        return False

def scan_tests_in_dir(directory):
    discovered_tests = []
    # Recursively walk directory
    for root, dirs, files in os.walk(directory):
        for filename in files:
            if not filename.endswith(".c"):
                continue
                
            filepath = os.path.join(root, filename)
            with open(filepath, 'r') as f:
                content = f.read()
                
                # Check for // FAIL
                if "// FAIL" in content:
                     discovered_tests.append((filepath, 0, True))
                     continue

                # Look for // RETURN: {int}
                match = re.search(r"//\s*RETURN:\s*(\d+)", content)
                if match:
                    expected_code = int(match.group(1))
                    discovered_tests.append((filepath, expected_code, False))
                
    return discovered_tests

def main():
    # Build compiler first
    print("Building compiler...", flush=True)
    if subprocess.run("swift build", shell=True).returncode != 0:
        print("Compiler build failed.")
        sys.exit(1)
        
    # Discovery
    final_tests = scan_tests_in_dir("tests")
    if not final_tests:
        print("No tests found.")
        sys.exit(0)
    
    # Sort for consistent output
    final_tests.sort(key=lambda x: x[0])
    
    total = len(final_tests)
    passed = 0
    
    for i, test in enumerate(final_tests):
        filepath, expected, expect_fail = test
        if test_file(filepath, expected, expect_fail, i+1, total):
            passed += 1
            
    print(f"\nSummary: {passed}/{total} tests passed.")
    if passed != total:
        sys.exit(1)

if __name__ == "__main__":
    main()
