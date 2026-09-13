// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "cauchyQ/moonbit-slotplan"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/cauchyQ/moonbit-slotplan"

license = "Apache-2.0"

keywords = [
  "scheduling",
  "booking",
  "availability",
  "interval",
  "resource-allocation",
]

preferred_target = "wasm"

description = "Deterministic interval and multi-resource booking algorithms for MoonBit"

import {
  "moonbit-community/rabbita@0.15.7",
}
