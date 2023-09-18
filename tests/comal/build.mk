COMAL_TESTS = $(wildcard tests/comal/*.cml)

.PHONY: comal-tests
comal-tests: $(patsubst %.cml,$(OBJDIR)/%.stamp,$(COMAL_TESTS))

$(OBJDIR)/tests/comal/%.stamp: tests/comal/%.good $(OBJDIR)/tests/comal/%.log
	diff -u $^ | tee $(patsubst %.stamp,%.diff,$@)
	touch $@

$(OBJDIR)/tests/comal/%.log: tests/comal/%.cml $(OBJDIR)/comal.com bin/cpmemu
	@mkdir -p $(dir $@)
	timeout 1s bin/cpmemu -p A=$(dir $<) $(OBJDIR)/comal.com $(notdir $<) > $@

