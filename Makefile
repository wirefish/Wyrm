# Client-facing files: html, css, js, images, and icons.

BUILDDIR = .build
CLIENTDIR = $(BUILDDIR)/client
MDFILES = $(wildcard client/*.md)
CPFILES = $(wildcard client/*.css) $(wildcard client/*.js) client/game.html

.PHONY: all server client html images fonts icons

all: server client

server:
	swift build

client: html images fonts icons

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
$(FONTDIR)/%: client/fonts/% | $(FONTDIR)
	cp $< $@
$(FONTDIR):
	@mkdir -p $@

IMAGEDIR = $(BUILDDIR)/client/images
IMAGES = $(wildcard client/images/*)
images: $(IMAGES:%=$(BUILDDIR)/%)
$(IMAGEDIR)/%: client/images/% | $(IMAGEDIR)
	cp $< $@
$(IMAGEDIR):
	@mkdir -p $@

# Icons

.PHONY: ui_icons

icons: $(IMAGEDIR)/neighbor_icons.png $(IMAGEDIR)/inventory_icons.png \
	$(IMAGEDIR)/avatar_icons.png ui_icons

$(IMAGEDIR)/neighbor_icons.png: tools/make_icons.py client/icons.txt | $(IMAGEDIR)
	tools/make_icons.py -n neighbor -s 34 -g items -g creatures -g avatars -g other \
		-o $(IMAGEDIR) client/icons.txt
	mv $(IMAGEDIR)/neighbor_icons.css $(CLIENTDIR)

$(IMAGEDIR)/inventory_icons.png: tools/make_icons.py client/icons.txt | $(IMAGEDIR)
	tools/make_icons.py -n inventory -s 24 -g items \
		-o $(IMAGEDIR) client/icons.txt
	mv $(IMAGEDIR)/inventory_icons.css $(CLIENTDIR)

$(IMAGEDIR)/avatar_icons.png: tools/make_icons.py client/icons.txt | $(IMAGEDIR)
	tools/make_icons.py -n avatar -s 60 -g avatars \
		-o $(IMAGEDIR) client/icons.txt
	mv $(IMAGEDIR)/avatar_icons.css $(CLIENTDIR)

ICONDIR = $(CLIENTDIR)/icons
ICONS = $(wildcard client/icons/*.png)

ui_icons: $(ICONS:%=$(BUILDDIR)/%)

$(ICONDIR)/%: client/icons/% | $(ICONDIR)
	cp $< $@

$(ICONDIR):
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
