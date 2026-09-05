// BTI accepts only the four HINT immediates 32/34/36/38 (any/c/j/jc).
// Expected failure: bti: kind must be one of the arm64_bti_* constants
import("arm/arm64.inc");

arm64_bti(33)
