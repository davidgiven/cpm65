COMAL_TESTS = $(wildcard tests/comal/*.cml)

.PHONY: comal-tests
comal-tests: $(patsubst %.cml,$(OBJDIR)/%.stamp,$(COMAL_TESTS))

$(OBJDIR)/tests/comal/%.stamp: tests/comal/%.good $(OBJDIR)/tests/comal/%.log
	rm -f $@
	diff -a -u $^ > $(patsubst %.stamp,%.diff,$@) || (cat $(patsubst %.stamp,%.diff,$@); exit 1)
	touch $@

$(OBJDIR)/tests/comal/%.log: tests/comal/%.cml $(OBJDIR)/comal.com bin/cpmemu
	@mkdir -p $(dir $@)
	timeout 4s bin/cpmemu -p A=$(dir $<) $(OBJDIR)/comal.com $(notdir $<) > $@

