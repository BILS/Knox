
TIFFS=$(wildcard img/*.tiff)
PNGS=$(TIFFS:%.tiff=%.png)

MD=markdown_py
EXTENSIONS=markdown.extensions.codehilite markdown.extensions.fenced_code markdown.extensions.tables

.PHONY: open
.SUFFIXES: .tiff .png .md .html

all: docs.html internal.html micromosler.html $(PNGS)

.md.html: 
	@echo "Compiling $< into $@"
	@$(MD) $< ${EXTENSIONS:%=-x %} -f $@

clean:
	rm -f docs.html current.html internal.html
	rm -f img/*.png

%.png:
	@echo "Converting $@ from $(@:.png=.tiff)"
	@sips -s format png $(@:.png=.tiff) --out $@ > /dev/null

echo:
	@echo "TIFF images"
	@echo $(TIFFS)
	@echo "PNG images"
	@echo $(PNGS)

##################### DOCKER #####################

run:
	docker run --name knox -v $(shell pwd):/usr/share/nginx/html:rw -v $(shell pwd)/nginx.conf:/etc/nginx/nginx.conf:ro -p 80:80 -d docs

stop:
	docker stop knox
	docker rm knox

build:
	docker build -t docs .

ip:
	@echo ${DOCKER_HOST}
