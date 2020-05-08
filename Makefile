.PHONY: prep clean

build: prep
	@./package.py
	@find dist/ -iname "*szpm"

prep:
	@mkdir -p dist

clean: prep
	@rm -rf dist/*

fmt:
	rufo src

new-migration:
	@./new-migration.py

init:
	@echo "Give your addon a name. No spaces."
	@echo "Addon name?: "; \
	read NAME; \
	mkdir -p "src/db/addon/$${NAME}"; \
	sed -i "s/NAME/$${NAME}/" base.szpm.template; \
	mv base.szpm.template "$${NAME}.szpm.template"

test:
	@echo "there are no tests yet"
