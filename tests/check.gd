class_name Check
extends RefCounted

## Tiny assertion helper for the headless test scripts.
##
## Godot's assert() is stripped from release builds and does not halt here, so
## a failed assert would otherwise print and let the run report success. This
## records failures explicitly and sets the process exit code.

var failures := 0
var checks := 0


func that(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: %s" % message)
		print("  FAIL: %s" % message)


func near(a: float, b: float, tolerance: float, message: String) -> void:
	that(absf(a - b) <= tolerance, "%s (got %.4f, wanted %.4f +/- %.4f)"
			% [message, a, b, tolerance])


func finish(suite: String) -> int:
	if failures == 0:
		print("%s: all %d checks passed" % [suite, checks])
		return 0
	print("%s: %d of %d checks FAILED" % [suite, failures, checks])
	return 1
