import Testing
@testable import BOMCore

@Suite struct SPDXTests {
    @Test func knownLicence() {
        #expect(SPDX.isLicence("MIT"))
        #expect(!SPDX.isLicence("mit"))
        #expect(SPDX.isLicenceAnyCase("mit"))
        #expect(!SPDX.isLicence("Classpath-exception-2.0"))
        #expect(SPDX.isExceptionAnyCase("classpath-exception-2.0"))
    }

    @Test(arguments: [
        "MIT", "MIT OR Apache-2.0", "mit or apache-2.0", "(MIT AND BSD-3-Clause) OR GPL-2.0-only",
        "GPL-2.0-or-later WITH Classpath-exception-2.0", "LicenseRef-acme", "DocumentRef-x:LicenseRef-y",
        "Apache-2.0+", " MIT\tOR\nISC ",
    ])
    func expressions(_ s: String) {
        #expect(SPDX.isValidExpression(s))
    }

    @Test(arguments: [
        "", "MIT OR", "(MIT", "MIT WITH MIT", "Foo-1.0", "MIT AND (", "MIT Or ISC", "MIT)", "LicenseRef-",
        String(repeating: "(", count: 65) + "MIT" + String(repeating: ")", count: 65),
        "MIT" + String(repeating: " OR MIT", count: 586),
    ])
    func badExpressions(_ s: String) {
        #expect(!SPDX.isValidExpression(s))
    }

    @Test func depthLimitIsSixtyFour() {
        #expect(SPDX.isValidExpression(String(repeating: "(", count: 64) + "MIT" + String(repeating: ")", count: 64)))
    }
}
