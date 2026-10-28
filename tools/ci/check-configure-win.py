#!/usr/bin/env python3
"""Exercise configure.win discovery and quoting without a Windows toolchain.

Run from any directory with Python 3, a POSIX shell, sed and GNU make:
    python3 tools/ci/check-configure-win.py

Every case runs in a disposable package copy with controlled PATH and Rtools
trees. pkg-config and R CMD SHLIB are explicit test doubles. GNU make and its
shell are real, so compiler argument quoting is checked after both expansion
steps. This harness does not compile, link or execute Windows code; native
Windows release jobs remain responsible for those checks.
"""

import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


PACKAGE = Path(__file__).resolve().parents[2]
SHELL = shutil.which("sh")
MAKE = shutil.which("make")


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!{sys.executable}\n" + text, encoding="utf-8")
    path.chmod(0o755)


FAKE_R = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
event = {"kind": "R", "args": args, "executable": sys.argv[0],
         "cflags": os.environ.get("PKG_CPPFLAGS", ""),
         "libs": os.environ.get("PKG_LIBS", "")}
is_probe = args[:2] == ["CMD", "SHLIB"]
bad_marker = os.environ.get("MOCK_R_FAIL_CONTAINS", "")
flags = event["cflags"] + " " + event["libs"]
failed = is_probe and (os.environ.get("MOCK_R_PROBE_FAIL") == "1" or
                      (bool(bad_marker) and bad_marker in flags))
event["ok"] = not failed
with open(os.environ["MOCK_TRACE"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps(event) + "\n")
if args[:2] == ["CMD", "config"]:
    value = os.environ.get("MOCK_R_CONFIG_" + args[-1], "")
    if not value:
        sys.exit(1)
    print(value)
elif args[:3] == ["--vanilla", "--slave", "-e"]:
    # Model the guarded query's result, not an R interpreter or version check.
    print(os.environ.get("MOCK_LEGACY_ROOT", ""))
elif is_probe:
    if failed:
        print("Mock R CMD SHLIB: requested compile/link failure", file=sys.stderr)
        sys.exit(1)
    # Creating these only satisfies file-existence checks; neither is a binary.
    for suffix in ("dll", "so"):
        pathlib.Path("conftest." + suffix).write_text("test double\n")
    if "-o" in args:
        pathlib.Path(args[args.index("-o") + 1]).write_text("test double\n")
else:
    print("Unexpected mock R invocation: " + repr(args), file=sys.stderr)
    sys.exit(2)
'''


class ConfigureWinTests(unittest.TestCase):
    def setUp(self):
        if not SHELL or not MAKE:
            self.fail("The configuration harness requires sh and GNU make.")
        temp_root = Path(tempfile.gettempdir()).resolve()
        # A caller can set TMPDIR to its checkout. Keep fixtures and their
        # executable symlinks outside the package, including during audits.
        if temp_root == PACKAGE or PACKAGE in temp_root.parents:
            temp_root = PACKAGE.parent
        self.temporary = tempfile.TemporaryDirectory(prefix="oecd-configure-win-", dir=temp_root)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = self.root / "package"
        (self.package / "src").mkdir(parents=True)
        shutil.copy2(PACKAGE / "configure.win", self.package / "configure.win")
        shutil.copy2(PACKAGE / "src" / "Makevars.in", self.package / "src" / "Makevars.in")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Keep host pkg-config and compiler installations outside the test PATH.
        for command in ("cat", "sed", "rm", "dirname", "basename", "tr", "grep",
                        "uname", "readlink", "expr", "head", "tail"):
            origin = shutil.which(command)
            if origin:
                (self.bin / command).symlink_to(origin)
        self.rhome = self.root / "R home"
        executable(self.rhome / "bin" / "R.exe", FAKE_R)
        executable(self.rhome / "bin" / "R", FAKE_R)
        self.trace = self.root / "trace.jsonl"
        self.env = {
            "PATH": str(self.bin), "R_HOME": str(self.rhome),
            "MOCK_TRACE": str(self.trace), "LC_ALL": "C",
            "TMPDIR": str(self.root),
        }

    def toolchain(self, name="target", dependencies=("lzma", "iconv", "z")):
        root = self.root / name
        headers = root / "include" / "libxml2" / "libxml"
        headers.mkdir(parents=True)
        (headers / "parser.h").write_text("/* fixture header, not compilable */\n")
        (headers / "xmlversion.h").write_text("#define LIBXML_VERSION 20914\n")
        (root / "lib").mkdir()
        (root / "bin").mkdir()
        for library in ("xml2", *dependencies):
            (root / "lib" / f"lib{library}.a").write_text("fixture archive\n")
        return root

    def pkg_config(self, directory, prefix, label="path", mode="good"):
        settings = {
            "label": label, "mode": mode,
            "cflags": f'-I"{prefix}/include/libxml2" -DMOCK_PKG_{label.upper()}=1',
            "libs": f'-L"{prefix}/lib" -lxml2 -lz',
        }
        executable(directory / "pkg-config", f"settings = {settings!r}\n" + r'''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["MOCK_TRACE"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"kind": "pkg-config", "args": args,
                             "label": settings["label"]}) + "\n")
if "--cflags" in args:
    if settings["mode"] == "cflags-fail":
        sys.exit(1)
    print(settings["cflags"])
elif "--libs" in args:
    if settings["mode"] == "libs-fail":
        sys.exit(1)
    print("" if settings["mode"] == "empty-libs" else settings["libs"])
elif "--exists" in args:
    # Discovery should not depend on this command alone: broken installations
    # can pass --exists while later flag queries or linking fail.
    sys.exit(0)
else:
    sys.exit(2)
''')

    def events(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] \
            if self.trace.exists() else []

    def configure(self, success=True):
        result = subprocess.run([SHELL, "configure.win"], cwd=self.package,
                                env=self.env, capture_output=True, text=True,
                                timeout=20)
        transcript = result.stdout + result.stderr
        output = self.package / "src" / "Makevars.win"
        if success:
            self.assertEqual(result.returncode, 0, transcript)
            self.assertTrue(output.is_file(), transcript)
            self.assertNotIn("@xml_", output.read_text())
            self.assertTrue(any(e["kind"] == "R" and e["args"][:2] == ["CMD", "SHLIB"]
                                and e["ok"] for e in self.events()),
                            "Successful configuration must validate its compiler/linker flags")
        else:
            self.assertNotEqual(result.returncode, 0, transcript)
            self.assertFalse(output.exists(), "Failure left a usable-looking Makevars.win")
        return transcript

    def compiler_arguments(self):
        capture = self.root / "arguments.json"
        script = self.root / "capture-arguments.py"
        script.write_text("import json, pathlib, sys\n"
                          f"pathlib.Path({str(capture)!r}).write_text(json.dumps(sys.argv[1:]))\n")
        makefile = self.package / "probe.mk"
        makefile.write_text("include src/Makevars.win\n"
                            "all:\n\t@" + shlex.quote(sys.executable) + " " +
                            shlex.quote(str(script)) + " $(PKG_CPPFLAGS) $(PKG_LIBS)\n")
        result = subprocess.run([MAKE, "--no-print-directory", "-f", "probe.mk"],
                                cwd=self.package, env=self.env, capture_output=True,
                                text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        raw = iter(json.loads(capture.read_text()))
        # Both -I"directory" and -I "directory" are valid compiler spellings.
        return [arg + next(raw) if arg in ("-I", "-L") else arg for arg in raw]

    def assert_toolchain_flags(self, root, dependencies=("lzma", "iconv", "z")):
        arguments = self.compiler_arguments()
        self.assertIn(f"-I{root}/include/libxml2", arguments)
        self.assertIn(f"-I{root}/include", arguments)
        self.assertIn(f"-L{root}/lib", arguments)
        self.assertIn("-DLIBXML_STATIC", arguments)
        libraries = [arg for arg in arguments if arg.startswith("-l")]
        self.assertEqual(libraries, ["-lxml2", *[f"-l{x}" for x in dependencies], "-lm", "-lws2_32"])

    def test_missing_pkg_config_uses_r_tools_soft(self):
        root = self.toolchain()
        self.env["R_TOOLS_SOFT"] = str(root)
        self.configure()
        self.assert_toolchain_flags(root)

    def test_missing_pkg_config_uses_local_soft(self):
        root = self.toolchain()
        self.env["LOCAL_SOFT"] = str(root)
        self.configure()
        self.assert_toolchain_flags(root)

    def test_r_tools_soft_precedes_local_soft(self):
        first = self.toolchain("first")
        second = self.toolchain("second")
        self.env.update(R_TOOLS_SOFT=str(first), LOCAL_SOFT=str(second))
        self.configure()
        self.assert_toolchain_flags(first)

    def test_r_configuration_can_supply_toolchain_root(self):
        root = self.toolchain()
        self.env["MOCK_R_CONFIG_R_TOOLS_SOFT"] = str(root)
        self.configure()
        self.assert_toolchain_flags(root)

    def test_compiler_relative_discovery_supports_rtools40(self):
        root = self.toolchain("legacy toolchain")
        executable(root / "bin" / "gcc", "raise SystemExit('Use R CMD SHLIB for the probe')\n")
        self.env.update(MOCK_R_CONFIG_CC="gcc -m64", PATH=str(root / "bin") + ":" + str(self.bin))
        self.configure()
        self.assert_toolchain_flags(root)

    def test_malformed_cc_does_not_block_explicit_flags(self):
        custom = self.toolchain("custom installation")
        self.env.update(MOCK_R_CONFIG_CC='"missing compiler -m64',
                        LIBXML_CFLAGS=f'-I"{custom}/include/libxml2" -DMOCK_EXPLICIT=1',
                        LIBXML_LIBS=f'-L"{custom}/lib" -lcustomxml')
        self.configure()
        arguments = self.compiler_arguments()
        self.assertIn("-DMOCK_EXPLICIT=1", arguments)
        self.assertIn("-lcustomxml", arguments)

    def test_guarded_legacy_query_handles_quoted_compiler_prefix(self):
        root = self.toolchain("legacy Rtools/mingw64")
        executable(root / "bin" / "gcc", "raise SystemExit('Use R CMD SHLIB for the probe')\n")
        self.env.update(MOCK_R_CONFIG_CC=f'"{root}/bin/"gcc -m64', MOCK_LEGACY_ROOT=str(root))
        self.configure()
        self.assert_toolchain_flags(root)
        self.assertTrue(any(e["kind"] == "R" and
                            e["args"][:3] == ["--vanilla", "--slave", "-e"]
                            for e in self.events()))

    def test_legacy_root_requires_guard_output_headers_and_archive(self):
        root = self.toolchain("legacy Rtools/mingw64")
        self.env.update(MOCK_LEGACY_ROOT=str(root), RTOOLS40_HOME=str(root.parent))
        required = (root / "include" / "libxml2" / "libxml" / "parser.h",
                    root / "lib" / "libxml2.a")
        for path in required:
            with self.subTest(missing=path.name):
                saved = path.read_bytes()
                path.unlink()
                self.configure(success=False)
                path.write_bytes(saved)
        # An empty query result models modern R declining the legacy layout.
        # A stale RTOOLS40_HOME alone must not cause the libraries to be used.
        self.env["MOCK_LEGACY_ROOT"] = ""
        self.configure(success=False)

    def test_working_path_pkg_config_is_used(self):
        prefix = self.toolchain("pkg installation")
        self.pkg_config(self.bin, prefix)
        self.configure()
        arguments = self.compiler_arguments()
        self.assertIn("-DMOCK_PKG_PATH=1", arguments)
        self.assertIn(f"-I{prefix}/include/libxml2", arguments)
        self.assertIn(f"-L{prefix}/lib", arguments)
        self.assertIn("-DLIBXML_STATIC", arguments)

    def test_target_pkg_config_precedes_path_pkg_config(self):
        target = self.toolchain()
        host = self.toolchain("host")
        self.env["R_TOOLS_SOFT"] = str(target)
        self.pkg_config(target / "bin", target, "target")
        self.pkg_config(self.bin, host, "host")
        self.configure()
        arguments = self.compiler_arguments()
        self.assertIn("-DMOCK_PKG_TARGET=1", arguments)
        self.assertNotIn("-DMOCK_PKG_HOST=1", arguments)

    def test_explicit_pkg_config_path_precedes_other_installations(self):
        target = self.toolchain()
        chosen = self.toolchain("chosen libraries")
        directory = self.root / "chosen pkg-config program"
        self.env.update(R_TOOLS_SOFT=str(target), PKG_CONFIG=str(directory / "pkg-config"))
        self.pkg_config(target / "bin", target, "target")
        self.pkg_config(self.bin, target, "path")
        self.pkg_config(directory, chosen, "chosen")
        self.configure()
        self.assertIn("-DMOCK_PKG_CHOSEN=1", self.compiler_arguments())
        self.assertEqual({e["label"] for e in self.events() if e["kind"] == "pkg-config"},
                         {"chosen"})

    def test_r_arch_bin_selects_the_architecture_specific_r(self):
        target = self.toolchain()
        selected = self.rhome / "bin" / "x64" / "R.exe"
        executable(selected, FAKE_R)
        self.env.update(R_TOOLS_SOFT=str(target), R_ARCH_BIN="/x64")
        self.configure()
        probes = [e for e in self.events() if e["kind"] == "R" and
                  e["args"][:2] == ["CMD", "SHLIB"]]
        self.assertEqual({e["executable"] for e in probes}, {str(selected)})

    def check_broken_pkg_config(self, mode):
        target = self.toolchain()
        self.env["R_TOOLS_SOFT"] = str(target)
        self.pkg_config(self.bin, self.toolchain("badpkg"), mode=mode)
        self.configure()
        self.assert_toolchain_flags(target)

    def test_failed_cflags_query_uses_toolchain_fallback(self):
        self.check_broken_pkg_config("cflags-fail")

    def test_failed_libs_query_uses_toolchain_fallback(self):
        self.check_broken_pkg_config("libs-fail")

    def test_empty_pkg_config_libraries_use_toolchain_fallback(self):
        self.check_broken_pkg_config("empty-libs")

    def test_unlinkable_pkg_config_flags_use_toolchain_fallback(self):
        target = self.toolchain()
        self.env.update(R_TOOLS_SOFT=str(target), MOCK_R_FAIL_CONTAINS="MOCK_PKG_PATH")
        self.pkg_config(self.bin, self.toolchain("badpkg"))
        self.configure()
        self.assert_toolchain_flags(target)
        probes = [e for e in self.events() if e["kind"] == "R" and
                  e["args"][:2] == ["CMD", "SHLIB"]]
        self.assertTrue(any(not e["ok"] for e in probes))
        self.assertTrue(any(e["ok"] for e in probes))

    def test_toolchain_paths_with_spaces_survive_make_and_shell(self):
        target = self.toolchain("Rtools installation with spaces")
        self.env["R_TOOLS_SOFT"] = str(target)
        self.configure()
        self.assert_toolchain_flags(target)

    def test_explicit_flags_override_discovery(self):
        target = self.toolchain()
        custom = self.toolchain("custom installation")
        self.pkg_config(self.bin, target)
        self.env.update(R_TOOLS_SOFT=str(target),
                        LIBXML_CFLAGS=f'-I"{custom}/include/libxml2" -DMOCK_EXPLICIT=1',
                        LIBXML_LIBS=f'-L"{custom}/lib" -lcustomxml')
        self.configure()
        arguments = self.compiler_arguments()
        self.assertIn("-DMOCK_EXPLICIT=1", arguments)
        self.assertIn(f"-I{custom}/include/libxml2", arguments)
        self.assertIn(f"-L{custom}/lib", arguments)
        self.assertIn("-lcustomxml", arguments)
        self.assertFalse(any(e["kind"] == "pkg-config" for e in self.events()))

    def test_explicit_directories_preserve_spaces(self):
        custom = self.toolchain("custom installation")
        self.env.update(INCLUDE_DIR=str(custom / "include" / "libxml2"),
                        LIB_DIR=str(custom / "lib"))
        self.configure()
        arguments = self.compiler_arguments()
        self.assertIn(f"-I{custom}/include/libxml2", arguments)
        self.assertIn(f"-L{custom}/lib", arguments)
        self.assertIn("-lxml2", arguments)

    def test_fallback_adds_only_present_static_dependencies(self):
        target = self.toolchain(dependencies=("z",))
        self.env["R_TOOLS_SOFT"] = str(target)
        self.configure()
        self.assert_toolchain_flags(target, dependencies=("z",))

    def test_missing_dependency_has_actionable_failure(self):
        transcript = self.configure(success=False)
        self.assertIn("libxml2", transcript)
        self.assertIn("Rtools", transcript)
        self.assertIn("LIBXML_CFLAGS", transcript)
        self.assertIn("LIBXML_LIBS", transcript)

    def test_compile_failure_removes_stale_makevars(self):
        target = self.toolchain()
        self.env.update(R_TOOLS_SOFT=str(target), MOCK_R_PROBE_FAIL="1")
        (self.package / "src" / "Makevars.win").write_text("PKG_LIBS = stale\n")
        transcript = self.configure(success=False)
        self.assertIn("Mock R CMD SHLIB", transcript)
        self.assertIn("libxml2", transcript)


if __name__ == "__main__":
    print("configure.win branch/quoting tests using mocked R and pkg-config.\n"
          "GNU make and shell expansion are real; this is not a Windows compilation test.",
          flush=True)
    unittest.main(verbosity=2)
