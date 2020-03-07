all : amoeba_test
		

clean : 
		rm test.gcda test.gcno amoebalib.o amoeba_test a.out amoebad.o

amoeba_test : test.c amoeba.d amoeba.h
		dmd -betterC -c amoeba.d -ofamoebad.o
		gcc -ggdb -Wall -fprofile-arcs -ftest-coverage -O0 -Wextra -pedantic -std=c89 -o amoeba_test amoebad.o test.c

test : amoeba_test
		./amoeba_test

