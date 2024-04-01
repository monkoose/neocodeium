.PHONY: test

test:
	nvim --headless -c "PlenaryBustedDirectory tests/ {sequential = true}"
