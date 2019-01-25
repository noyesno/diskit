

t:
	gcc -o walkdir src/walkdir.c


.PHONY: diskstat.kit
diskstat.kit :
	sdx wrap $@
