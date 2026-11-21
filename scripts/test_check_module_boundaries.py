#!/usr/bin/env python3
"""
scripts/test_check_module_boundaries.py

Unit test suite verifying scripts/check_module_boundaries.
Asserts clean run on current tree and actionable failures on intentional violating fixtures.
"""

import json
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
        self.assertIn("All 34 intentional violation fixtures caught", res.stdout)

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

    def test_portable_core_violating_import_class_uikit(self):
        fixture = "import class UIKit.UIView\nclass X {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_UNAUTHORIZED_IMPORT_UIKIT" for v in violations))

    def test_portable_core_violating_canimport_uikit(self):
        fixture = "#if canImport(UIKit)\nclass X {}\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_PLATFORM_IF" for v in violations))

    def test_portable_core_violating_elseif_platform(self):
        fixture = "#if DEBUG\n#elseif os(iOS)\nclass X {}\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_PLATFORM_IF" for v in violations))

    def test_portable_core_violating_target_environment(self):
        fixture = "#if targetEnvironment(simulator)\nclass X {}\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_FORBIDDEN_PLATFORM_IF" for v in violations))

    def test_portable_core_violating_unauthorized_activitykit_conditional(self):
        fixture = "#if canImport(ActivityKit)\nclass X {}\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_UNAUTHORIZED_ACTIVITYKIT_CONDITIONAL" for v in violations))

    def test_portable_core_violating_unauthorized_watchos_conditional(self):
        fixture = "#if os(watchOS)\nclass X {}\n#endif"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "CORE_UNAUTHORIZED_WATCHOS_CONDITIONAL" for v in violations))

    def test_ios_boundary_missing_if_guard(self):
        fixture = "import UIKit\npublic class SomeHelper {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/SomeHelper.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "IOS_MISSING_IF_GUARD" for v in violations))

    def test_ios_boundary_comment_only_guard_fails(self):
        fixture = "// TODO: wrap in #if os(iOS)\nimport UIKit\npublic class SomeHelper {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/SomeHelper.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "IOS_MISSING_IF_GUARD" for v in violations))

    def test_ios_boundary_code_after_endif_fails(self):
        fixture = "#if os(iOS)\npublic class SomeHelper {}\n#endif\npublic class UnprotectedHelper {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/SomeHelper.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "IOS_MISSING_IF_GUARD" for v in violations))

    def test_ios_boundary_spaced_guard_passes(self):
        fixture = "#if os( iOS )\nimport UIKit\npublic class SomeHelper {}\n#endif // os(iOS)"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/SomeHelper.swift", fixture, sanitized)
        self.assertEqual(len(violations), 0)

    def test_portable_core_access_level_imports(self):
        cases = {
            "internal import UIKit": "CORE_UNAUTHORIZED_IMPORT_UIKIT",
            "public import WidgetKit": "CORE_FORBIDDEN_IMPORT_WIDGETKIT",
            "package import ActivityKit": "CORE_FORBIDDEN_IMPORT_ACTIVITYKIT",
            "fileprivate import UIKit": "CORE_UNAUTHORIZED_IMPORT_UIKIT",
            "private import WidgetKit": "CORE_FORBIDDEN_IMPORT_WIDGETKIT",
            "@preconcurrency internal import UIKit": "CORE_UNAUTHORIZED_IMPORT_UIKIT",
            "import Foundation; import WidgetKit": "CORE_FORBIDDEN_IMPORT_WIDGETKIT",
        }
        for imports, rule in cases.items():
            fixture = f"{imports}\nstruct X {{}}"
            sanitized = checker.sanitize_code(fixture)
            violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
            self.assertTrue(any(v.rule_id == rule for v in violations), f"Failed for {imports!r}")

    def test_watch_access_level_import(self):
        fixture = "public import WidgetKit\nstruct View {}"
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_watch_file("OBAKitWatch/Screens/View.swift", fixture, sanitized)
        self.assertTrue(any(v.rule_id == "WATCH_FORBIDDEN_IMPORT_WIDGETKIT" for v in violations))

    def test_ios_boundary_guard_with_else_branch_fails(self):
        for branch in ("#else", "#elseif os(watchOS)"):
            fixture = f"#if os(iOS)\npublic class A {{}}\n{branch}\npublic class B {{}}\n#endif"
            sanitized = checker.sanitize_code(fixture)
            violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/A.swift", fixture, sanitized)
            self.assertTrue(any(v.rule_id == "IOS_MISSING_IF_GUARD" for v in violations), f"Failed for {branch}")

    def test_ios_boundary_compound_guard_fails(self):
        for condition in ("os(iOS) || os(watchOS)", "os(iOS) || DEBUG"):
            fixture = f"#if {condition}\npublic class A {{}}\n#endif"
            sanitized = checker.sanitize_code(fixture)
            violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/A.swift", fixture, sanitized)
            self.assertTrue(any(v.rule_id == "IOS_MISSING_IF_GUARD" for v in violations), f"Failed for {condition}")

    def test_ios_boundary_nested_else_and_access_level_imports_pass(self):
        fixture = (
            "public import Foundation; internal import UIKit\n"
            "#if os(iOS) // os(iOS)\n"
            "#if DEBUG\nlet a = 1\n#else\nlet a = 2\n#endif\n"
            "#endif // os(iOS)"
        )
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_ios_boundary_file("OBAKitCore/iOS/UIKit/A.swift", fixture, sanitized)
        self.assertEqual(violations, [])

    def test_sanitizer_keeps_interpolated_code(self):
        fixture = 'let name = "app: \\(UIApplication.shared) and UIView"'
        sanitized = checker.sanitize_code(fixture)
        self.assertIn("UIApplication.shared", sanitized)
        self.assertNotIn("UIView", sanitized)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertEqual([v.rule_id for v in violations], ["CORE_FORBIDDEN_UIAPPLICATION"])

    def test_sanitizer_handles_nested_strings_in_interpolation(self):
        fixture = 'let s = "a \\(f("UIView", g(1))) b"\nlet x = UIApplication.shared'
        sanitized = checker.sanitize_code(fixture)
        self.assertNotIn("UIView", sanitized)
        self.assertIn("f(", sanitized)
        self.assertIn("UIApplication.shared", sanitized)

    def test_sanitizer_handles_raw_strings(self):
        fixture = (
            'let path = #"C:\\"#\n'
            'let text = #"import UIKit "quoted" \\(UIView)"#\n'
            'let real = ##"a \\##(UIApplication.shared) "# b"##\n'
            "let x = 1"
        )
        sanitized = checker.sanitize_code(fixture)
        self.assertEqual(fixture.count("\n"), sanitized.count("\n"))
        self.assertEqual(len(fixture), len(sanitized))
        self.assertNotIn("UIKit", sanitized)
        self.assertNotIn("UIView", sanitized)
        self.assertNotIn("quoted", sanitized)
        self.assertIn("UIApplication.shared", sanitized)
        self.assertIn("let x = 1", sanitized)

    def test_sanitizer_single_line_raw_string_of_quotes(self):
        fixture = 'let quote = #"""#\nimport ActivityKit\nlet x = 1'
        sanitized = checker.sanitize_code(fixture)
        self.assertIn("import ActivityKit", sanitized)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        v = next(v for v in violations if v.rule_id == "CORE_FORBIDDEN_IMPORT_ACTIVITYKIT")
        self.assertEqual(v.line, 2)

    def test_sanitizer_raw_multiline_string_still_stripped(self):
        fixture = 'let text = #"""\nimport ActivityKit "# not the end\n"""#\nlet x = 1'
        sanitized = checker.sanitize_code(fixture)
        self.assertNotIn("ActivityKit", sanitized)
        self.assertIn("let x = 1", sanitized)

    def test_sanitizer_preserves_columns_after_interpolation(self):
        fixture = 'let s = "\\(a)"; let app = UIApplication.shared'
        sanitized = checker.sanitize_code(fixture)
        violations = checker.check_portable_core_file("OBAKitCore/Models/X.swift", fixture, sanitized)
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].column, fixture.index("UIApplication") + 1)

    def test_cli_json_verbose_stdout_is_only_json(self):
        script_path = REPO_ROOT / "scripts" / "check_module_boundaries"
        res = subprocess.run([sys.executable, str(script_path), "--json", "--verbose"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(json.loads(res.stdout), [])
        self.assertIn("Scanned", res.stderr)

    def test_find_repo_root_walks_up_from_subdirectory(self):
        sub_dir = REPO_ROOT / "OBAKit" / "Stops"
        found = checker.find_repo_root(sub_dir)
        self.assertEqual(found, REPO_ROOT)

    def test_find_repo_root_outside_repo_returns_none(self):
        found = checker.find_repo_root(Path(tempfile.gettempdir()))
        # In /tmp there is no Package.swift / OBAKitCore
        if not (Path(tempfile.gettempdir()) / "Package.swift").exists():
            self.assertIsNone(found)

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
