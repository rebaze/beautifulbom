# rio fixtures

`bsi-pass.cdx.json` and `bsi-fail.cdx.json` are synthetic SBOMs from rio
(https://github.com/rebaze/rio, `testdata/profile/`), licensed under the Apache License 2.0.
They are rio's own reference cases for its `bsi-tr-03183-2@2.1.0` profile; the parity tests
run the app's checks on them and compare with rio's results in `../parity/`.

`../edge/bsi-pass-broken.cdx.json` is `bsi-pass.cdx.json` with two stray commas before the last brace: a file rio refuses to read, for the test that a broken file never gets the all-present verdict.
