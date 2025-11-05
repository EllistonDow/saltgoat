import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "pwa_helpers.py"


class PwaPatchHelpersTest(unittest.TestCase):
    def run_cli(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True,
            text=True,
            check=check,
        )

    def test_patch_talon(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "talon.js"
            path.write_text(
                textwrap.dedent(
                    """
                    const attributeLabelCompare = (attribute1, attribute2) => {
                        const label1 = attribute1['attribute_metadata']['label'].toLowerCase();
                        const label2 = attribute2['attribute_metadata']['label'].toLowerCase();
                        if (label1 < label2) return -1;
                        else if (label1 > label2) return 1;
                        else return 0;
                    };

                    const getCustomAttributes = (product, optionCodes, optionSelections) => {
                        const { custom_attributes, variants } = product;
                        const isConfigurable = isProductConfigurable(product);
                        const optionsSelected =
                            Array.from(optionSelections.values()).filter(value => !!value).length >
                            0;

                        if (isConfigurable && optionsSelected) {
                            const item = findMatchingVariant({
                                optionCodes,
                                optionSelections,
                                variants
                            });

                            return item && item.product
                                ? [...item.product.custom_attributes].sort(attributeLabelCompare)
                                : [];
                        }

                        return custom_attributes
                            ? [...custom_attributes].sort(attributeLabelCompare)
                            : [];
                    };
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )
            proc = self.run_cli("patch-talon", "--file", str(path))
            self.assertEqual(proc.stdout.strip(), "patched")
            content = path.read_text(encoding="utf-8")
            self.assertIn("attribute1?.attribute_metadata?.label", content)

    def test_sanitize_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "checkout.gql.js"
            path.write_text(
                textwrap.dedent(
                    """
                    selected_payment_method {
                        ... on SomeInterface {
                            foo
                        }
                    }
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )
            proc = self.run_cli("sanitize-checkout", "--file", str(path))
            self.assertEqual(proc.stdout.strip(), "patched")
            sanitized = path.read_text(encoding="utf-8")
            self.assertIn("__typename", sanitized)
            self.assertNotIn("SomeInterface", sanitized)

    def test_remove_and_replace_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "snippet.js"
            path.write_text(
                "a\nremove-me\nconst demo = 1;\n", encoding="utf-8"
            )
            proc = self.run_cli("remove-line", "--file", str(path), "--contains", "remove-me")
            self.assertEqual(proc.stdout.strip(), "removed")
            proc = self.run_cli(
                "replace-line",
                "--file",
                str(path),
                "--old",
                "const demo = 1;",
                "--new",
                "const demo = 2;",
            )
            self.assertEqual(proc.stdout.strip(), "replaced")
            self.assertIn("const demo = 2;", path.read_text(encoding="utf-8"))

    def test_add_guard_and_tune_webpack(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            intercept = Path(tmp) / "intercept.js"
            intercept.write_text(
                "module.exports = targets => {\n    // noop\n}\n",
                encoding="utf-8",
            )
            proc = self.run_cli(
                "add-guard",
                "--file",
                str(intercept),
                "--env-var",
                "MAGENTO_DEMO_ENABLED",
            )
            self.assertEqual(proc.stdout.strip(), "patched")
            guarded = intercept.read_text(encoding="utf-8")
            self.assertIn("MAGENTO_DEMO_ENABLED", guarded)

            webpack = Path(tmp) / "webpack.config.js"
            webpack.write_text(
                "module.exports = (env = {}) => {\n    const config = {};\n    return [config];\n};\n",
                encoding="utf-8",
            )
            proc = self.run_cli("tune-webpack", "--file", str(webpack))
            self.assertEqual(proc.stdout.strip(), "patched")
            tuned = webpack.read_text(encoding="utf-8")
            self.assertIn("config.performance.hints = false", tuned)

    def test_env_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_file = Path(tmp) / ".env"
            proc = self.run_cli(
                "ensure-env-default",
                "--file",
                str(env_file),
                "--key",
                "FOO",
                "--value",
                "bar",
            )
            self.assertEqual(proc.returncode, 0)
            proc = self.run_cli(
                "ensure-env-default",
                "--file",
                str(env_file),
                "--key",
                "FOO",
                "--value",
                "baz",
            )
            self.assertEqual(proc.returncode, 0)
            self.assertIn("FOO=bar", env_file.read_text(encoding="utf-8"))
            value = self.run_cli("get-env", "--file", str(env_file), "--key", "FOO")
            self.assertEqual(value.stdout.strip(), "bar")

    def test_patch_product_fragment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fragment.js"
            path.write_text(
                "custom_attributes {\n  attribute_metadata {\n  }\n  selected_attribute_options\n}\n",
                encoding="utf-8",
            )
            proc = self.run_cli("patch-product-fragment", "--file", str(path))
            self.assertEqual(proc.stdout.strip(), "patched")
            content = path.read_text(encoding="utf-8")
            self.assertNotIn("attribute_metadata", content)
            self.assertNotIn("selected_attribute_options", content)

    def test_load_config_and_graphql_checks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "magento-pwa.sls"
            config.write_text(
                textwrap.dedent(
                    """
                    magento_pwa:
                      sites:
                        bank:
                          root: /var/www/bank
                          base_url: http://bank.test/
                          admin:
                            frontname: adminpanel
                          db:
                            name: bankdb
                    """
                ),
                encoding="utf-8",
            )
            proc = self.run_cli("load-config", "--config", str(config), "--site", "bank")
            exports = dict(line.split("=", 1) for line in proc.stdout.strip().splitlines())
            self.assertEqual(json.loads(exports["PWA_SITE_NAME"]), "bank")
            self.assertEqual(json.loads(exports["PWA_DB_NAME"]), "bankdb")

        ok = self.run_cli(
            "validate-graphql",
            "--payload",
            json.dumps({"data": {"storeConfig": {"store_name": "Demo"}}}),
        )
        self.assertEqual(ok.returncode, 0)
        err = subprocess.run(
            [sys.executable, str(SCRIPT), "validate-graphql", "--payload", json.dumps({"errors": ["oops"]})],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(err.returncode, 0)

    def test_check_react_skip(self) -> None:
        output = self.run_cli("check-react", "--dir", "/tmp").stdout.strip()
        self.assertIn(output, {"", "skip"})


if __name__ == "__main__":
    unittest.main()
