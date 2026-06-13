.PHONY: test

test:
	nvim --headless -c "PlenaryBusted tests { keep_going = false }"
