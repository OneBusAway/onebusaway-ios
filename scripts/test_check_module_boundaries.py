#!/usr/bin/env python3
"""
scripts/test_check_module_boundaries.py

Unit test suite verifying scripts/check_module_boundaries.
Asserts clean run on current tree and actionable failures on intentional violating fixtures.
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from importlib.machinery import SourceFileLoader

REPO_ROOT = Path(__file__).resolve().parent.parent

# Load scripts/check_module_boundaries directly as a module
_script_path = REPO_ROOT / "scripts" / "check_module_boundaries"
checker = SourceFileLoader("check_module_boundaries", str(_script_path)).load_module()


class ModuleBoundaryCheckerTests(unittest.TestCase):

    def test_current_tree_is_clean(self):
        """Asserts that the actual repository tree contains 0 module boundary violations."""
        violations = checker.scan_tree(REPO_ROOT, verbose=False)
        if violations:
            msg = "\n".join(v.format_diagnostic() for v in violations)
            self.fail(f"Current repository tree unexpectedly has {len(violations)} violation(s):\n{msg}")

    def test_cli_executable_clean_run(self):
        """Runs the CLI executable on current tree and expects exit code 0."""
        script_path = REPO_ROOT / "scripts" / "check_module_boundaries"
        res = subprocess.run([sys.executable, str(script_path)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"CLI failed:\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}")
        self.assertIn("Module boundary check passed", res.stdout)

    def test_cli_test_flag(self):
        """Runs scripts/check_module_boundaries --test and expects exit code 0."""
        script_path = REPO_ROOT / "scripts" / "check_module_boundaries"
        res = subprocess.run([sys.executable, str(script_path), "--test"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"CLI --test failed:\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}")
        self.assertIn("All 16 intentional violation fixtures caught", res.stdout)

    def test_sanitizer_removes_comments_and_strings_accurately(self):
        """Tests that comments and string literals are sanitized without shifting lines or columns."""
        raw = (
            "// line 1 comment\n"
            "/* block\n"
            "   comment */\n"
            'let a = "hello string"\n'
            'let b = """multi\n'
            'line"""\n'
            "let c = 123"
        )
        sanitized = checker.sanitize_code(raw)
        self.assertEqual(raw.count("\n"), sanitized.count("\n"))
        self.assertNotIn("hello string", sanitized)
        self.assertNotIn("line 1 comment", sanitized)
        self.assertNotIn("block", sanitized)
        self.assertIn("let a =", sanitized)
        self.assertIn("let c = 123", sanitized)

    def test_portable_core_violating_import_activitykit(self):
        fixture = "import ActivityKit\nclass X {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_IMPORT_ACTIVITYKIT" for v in violations))
        v = next(v for v in violations if v.rule_id == "CORE_FORBIDDEN_IMPORT_ACTIVITYKIT")
        self.assertIn("ActivityKit is iOS-only", v.remediation)

    def test_portable_core_violating_import_widgetkit(self):
        fixture = "import WidgetKit\nclass X {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_IMPORT_WIDGETKIT" for v in violations))

    def test_portable_core_violating_unauthorized_import_uikit(self):
        fixture = "import UIKit\nclass X {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_UNAUTHORIZED_IMPORT_UIKIT" for v in violations))

    def test_portable_core_allowlisted_uikit_file_passes(self):
        fixture = "import UIKit\npublic extension UIColor { var test: Int { 1 } }"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Extensions/UIColor+Hex.swift", fixture, sanitized)
        self.assertEqual(len(violations), 0)

    def test_portable_core_allowlisted_file_with_uiview_fails(self):
        fixture = "import UIKit\nclass MyView: UIView {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Extensions/UIColor+Hex.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_UIKIT_VIEW" for v in violations))

    def test_portable_core_violating_uiapplication(self):
        fixture = "func check() { UIApplication.shared.open(url) }"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Utilities/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_UIAPPLICATION" for v in violations))

    def test_portable_core_violating_region_monitoring(self):
        fixture = "func check(mgr: CLLocationManager, r: CLRegion) { mgr.startMonitoring(for: r) }"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Location/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_REGION_MONITORING" for v in violations))

    def test_portable_core_violating_platform_if(self):
        fixture = "#if os(iOS)\nlet val = 1\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_PLATFORM_IF" for v in violations))

    def test_ios_boundary_missing_if_guard(self):
        fixture = "import UIKit\npublic class SomeHelper {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/SomeHelper.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "IOS_MISSING_IF_GUARD" for v in violations))

    def test_ios_boundary_extension_unsafe_uiapplication(self):
        fixture = "#if os(iOS)\nimport UIKit\nfunc open() { UIApplication.shared.open(url) }\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/SomeHelper.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "IOS_FORBIDDEN_UIAPPLICATION" for v in violations))

    def test_watch_violating_core_application(self):
        fixture = "class Host { let app = CoreApplication(config: cfg) }"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_watch_file("OBAKitWatch/Host/Host.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "WATCH_FORBIDDEN_CORE_APPLICATION" for v in violations))

    def test_watch_violating_imports(self):
        for mod in ("UIKit", "ActivityKit", "WidgetKit", "OBAKit"):
            fixture = f"import {mod}\nstruct View {{}}"
            sanitized = checker.sanitize_code(fixture)
            violations = checker.check_watch_file("OBAKitWatch/Screens/View.swift", fixture, sanitized)
            rule = f"WATCH_FORBIDDEN_IMPORT_{mod.upper()}"
            self.assertTrue(any(v.rule_id == rule for v in violations), f"Failed for {mod}")

    def test_obakit_violating_imports(self):
        for mod in ("OBAKitWatch", "WatchKit"):
            fixture = f"import {mod}\nclass Cont {{}}"
            sanitized = checker.sanitize_code(fixture)
            violations = checker.check_obakit_file("OBAKit/UI/Cont.swift", fixture, sanitized)
            rule = f"OBAKIT_FORBIDDEN_IMPORT_{mod.upper()}"
            self.assertTrue(any(v.rule_id == rule for v in violations), f"Failed for {mod}")


if __name__ == "__main__":
    unittest.main()
