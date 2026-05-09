"""
CAD Parser Regression Test
Run after EVERY change: python test_regression.py
ALL files must stay within tolerance. Failures = regression.
"""
import sys
import os

# Ensure we can import from modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from modules.cad_parser import parse_dxf_file

# Adjust paths to match actual file locations
FILES = {
    'building':   'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/building.dxf',
    'house_plan': 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house_plan.dxf',
    'house':      'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house.dxf',
}

# (expected_value, tolerance_percent)
# tolerance=0 means exact match required
EXPECTED = {
    'building': {
        'totalFloorArea':  (387.0, 5.0),   # 387m² ± 5%
        'totalWallLength': (215.0, 25.0),  # ~215m ± 25% (harder to measure exactly)
        'floorCount':      (4, 0),         # exactly 4
    },
    'house_plan': {
        'totalFloorArea':  (90.0, 15.0),   # 90-97m² ± 15%
        'totalWallLength': (84.0, 30.0),   # ~84m ± 30%
        'floorCount':      (1, 0),         # exactly 1
    },
    'house': {
        'totalFloorArea':  (342.0, 5.0),   # 342m² ± 5%
        'totalWallLength': (200.0, 25.0),  # was 45%, now 25% — 166.9m is 16.6% off
        'floorCount':      (2, 0),         # exactly 2
    },
}

def run():
    passed = failed = 0
    for name, path in FILES.items():
        print(f'\n--- {name} ---')
        if not os.path.exists(path):
            print(f'  FAIL: File not found at {path}')
            failed += 1
            continue
            
        try:
            r = parse_dxf_file(path)
            if r.get('error'):
                print(f'  FAIL: error={r["error"]}'); failed += 1; continue
            for field, (exp, tol) in EXPECTED[name].items():
                actual = r.get(field, 0)
                if tol == 0:
                    ok = (actual == exp)
                    print(f'  {"PASS" if ok else "FAIL"} {field}: {actual} (expected {exp})')
                else:
                    err = abs(actual - exp) / exp * 100 if exp else 100
                    ok = err <= tol
                    print(f'  {"PASS" if ok else "FAIL"} {field}: {actual:.1f} '
                          f'(expected {exp}, error={err:.1f}%, tol={tol}%)')
                passed += ok; failed += (not ok)
        except Exception as e:
            print(f'  EXCEPTION: {e}'); failed += 1

    print(f'\n{"="*50}')
    print(f'{"ALL PASSED" if not failed else "REGRESSION DETECTED"}: '
          f'{passed} passed, {failed} failed')
    if failed:
        print('Do NOT commit — fix regressions first.')
        sys.exit(1)

if __name__ == '__main__': run()
