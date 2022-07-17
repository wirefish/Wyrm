# Client-facing files: html, css, js, images, and icons.

BUILDDIR = .build
CLIENTDIR = $(BUILDDIR)/client
MDFILES = $(wildcard client/*.md)
CPFILES = $(wildcard client/*.css) $(wildcard client/*.js) client/game.html

.PHONY: client html images fonts
client: html images fonts

html: $(MDFILES:%.md=$(BUILDDIR)/%.html) $(CPFILES:%=$(BUILDDIR)/%)

$(CLIENTDIR)/%.html: client/%.md client/template.html | $(CLIENTDIR)
	pandoc -s --template client/template.html $< -o $@

$(CLIENTDIR)/game.html: client/game.html | $(CLIENTDIR)
	cp $< $@

$(CLIENTDIR)/%.js: client/%.js | $(CLIENTDIR)
	cp $< $@

$(CLIENTDIR)/%.css: client/%.css | $(CLIENTDIR)
	cp $< $@

$(CLIENTDIR):
	@mkdir -p $@

FONTDIR = $(CLIENTDIR)/fonts
FONTS = $(wildcard client/fonts/*.woff)
fonts: $(FONTS:%=$(BUILDDIR)/%)
$(CLIENTDIR)/fonts/%: client/fonts/% | $(FONTDIR)
	cp $< $@
$(FONTDIR):
	@mkdir -p $@

IMAGEDIR = $(BUILDDIR)/client/images
IMAGES = $(wildcard client/images/*)
images: $(IMAGES:%=$(BUILDDIR)/%)
$(CLIENTDIR)/images/%: client/images/% | $(IMAGEDIR)
	cp $< $@
$(IMAGEDIR):
	@mkdir -p $@

# Documentation

DOCDIR = $(BUILDDIR)/doc
DOCFILES = $(wildcard doc/*.md)
HTMLFILES = $(DOCFILES:%.md=$(BUILDDIR)/%.html) $(DOCDIR)/slots.html
PANDOC_OPTS = --toc --css doc.css -s

.PHONY: doc
doc: $(HTMLFILES) $(DOCDIR)/doc.css

$(DOCDIR)/slots.html: $(SRCDIR)/slots.h tools/make_slot_ref.py | $(DOCDIR)
	$(CURDIR)/tools/make_slot_ref.py < $< | pandoc $(PANDOC_OPTS) -o $@

$(DOCDIR)/%.html: doc/%.md | $(DOCDIR)
	pandoc $< $(PANDOC_OPTS) -o $@

$(DOCDIR)/%.css: doc/%.css | $(DOCDIR)
	cp $< $@

$(DOCDIR):
	@mkdir -p $@

# Package up a distribution

DISTDIR = ../dist/wyrm-$(shell date "+%Y%m%d")-$(BUILD)

.PHONY: dist
dist: $(BINDIR)/wyrm icons doc
	mkdir -p $(DISTDIR)/bin
	cp $(BINDIR)/wyrm $(DISTDIR)/bin
	cp -r $(DOCDIR) $(CLIENTDIR) config data world $(DISTDIR)

.PHONY: clean
clean:
	rm -r $(BUILDDIR)
