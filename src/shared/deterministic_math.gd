class_name DeterministicMath
extends RefCounted

## Platform-independent arithmetic for authoritative values.
##
## `pow()` comes from each platform's C math library, whose last-bit rounding
## differs between Windows and Linux/macOS. Servers and clients on different
## operating systems must derive identical stats, so integer powers use only
## IEEE-754 multiplication, which rounds identically everywhere.


static func int_pow(base: float, exponent: int) -> float:
	var result := 1.0
	var factor := base
	var remaining := absi(exponent)
	while remaining > 0:
		if remaining & 1:
			result *= factor
		factor *= factor
		remaining >>= 1
	return 1.0 / result if exponent < 0 else result
