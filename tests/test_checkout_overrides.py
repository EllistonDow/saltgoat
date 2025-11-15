import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


class CheckoutOverridesTest(unittest.TestCase):
    def test_checkout_talon_returns_list(self):
        content = (
            REPO_ROOT
            / "modules"
            / "pwa"
            / "overrides"
            / "packages"
            / "peregrine"
            / "lib"
            / "talons"
            / "CheckoutPage"
            / "useCheckoutPage.js"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "availablePaymentMethods:\n            checkoutData?.cart?.available_payment_methods || []",
            content,
        )

    def test_checkout_page_uses_resolved_methods(self):
        content = (
            REPO_ROOT
            / "modules"
            / "pwa"
            / "overrides"
            / "packages"
            / "venia-ui"
            / "lib"
            / "components"
            / "CheckoutPage"
            / "checkoutPage.js"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "const resolvedPaymentMethods = Array.isArray(availablePaymentMethods)",
            content,
        )
        self.assertIn("resolvedPaymentMethods.length > 0", content)

    def test_payment_methods_default_no_disable(self):
        content = (
            REPO_ROOT
            / "modules"
            / "pwa"
            / "overrides"
            / "packages"
            / "venia-ui"
            / "lib"
            / "components"
            / "CheckoutPage"
            / "PaymentInformation"
            / "paymentMethods.js"
        ).read_text(encoding="utf-8")
        self.assertNotIn(":'braintree'", content.replace(" ", ""))
        self.assertIn(
            "process.env.SALTGOAT_PWA_DISABLED_PAYMENTS ??\n        process.env.NEXT_PUBLIC_SALTGOAT_DISABLED_PAYMENTS ??\n        ''",
            content,
        )


if __name__ == "__main__":
    unittest.main()
