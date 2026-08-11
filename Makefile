.PHONY: help verify-tools validate

help:
	@printf '%s\n' 'Available targets:'
	@printf '%s\n' '  make verify-tools  Check required and optional local tools'
	@printf '%s\n' '  make validate      Run Stage 1 repository validation'

verify-tools:
	@bash scripts/verify-tools.sh

validate:
	@bash scripts/validate.sh
